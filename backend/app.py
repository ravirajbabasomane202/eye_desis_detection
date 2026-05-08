"""
Eye Disease Classification — Flask API  (v3.0 — Flask-SQLAlchemy)
=================================================================
v3 changes (on top of v2 full-feature set):
  - All in-memory state (_history list, _patients dict, _users dict)
    replaced with a persistent SQLite database via Flask-SQLAlchemy.
  - Three ORM models: Patient, User, Prediction
  - Zero breaking changes to any existing API endpoint or response shape.
"""

import os, sys, io, json, uuid, logging, argparse, traceback, tempfile, hashlib
from datetime import datetime, timedelta
from functools import lru_cache, wraps

import torch
import numpy as np
from flask import Flask, request, jsonify, abort, send_file
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from PIL import Image
import cv2

# Optional JWT — fall back gracefully if not installed
try:
    import jwt as pyjwt
    JWT_AVAILABLE = True
except ImportError:
    JWT_AVAILABLE = False
    logging.warning("PyJWT not installed — auth endpoints disabled. pip install PyJWT")

# Optional ReportLab for PDF
try:
    from reportlab.lib.pagesizes import A4
    from reportlab.lib import colors
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import cm
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, HRFlowable
    from reportlab.lib.enums import TA_CENTER, TA_LEFT
    PDF_AVAILABLE = True
except ImportError:
    PDF_AVAILABLE = False
    logging.warning("ReportLab not installed — PDF reports disabled. pip install reportlab")

from inference import load_models, run_inference, DISPLAY_CLASSES, DISEASE_DESCRIPTIONS

# ─── Logging ────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)

# ─── App & DB ────────────────────────────────────────────────────────
app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

# SQLite database stored next to app.py; override with DATABASE_URL env var
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get(
    "DATABASE_URL", f"sqlite:///{os.path.join(os.path.dirname(__file__), 'eyecheck.db')}"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db = SQLAlchemy(app)

JWT_SECRET = os.environ.get("JWT_SECRET", "eyecheck-secret-change-in-production")
JWT_EXPIRY_HOURS = 24
LOW_CONFIDENCE_THRESHOLD = 60.0   # % — warn below this
DUPLICATE_HASH_WINDOW = 50        # check last N history entries

# ─── Global model state (unchanged) ─────────────────────────────────
_models     = None
_device     = None
_model_dir  = None

ALLOWED_EXTENSIONS = {"jpg", "jpeg", "png", "bmp", "webp"}
MAX_FILE_SIZE_MB   = 20

# ═══════════════════════════════════════════════════════════════════
# SQLAlchemy Models
# ═══════════════════════════════════════════════════════════════════

class Patient(db.Model):
    __tablename__ = "patients"

    patient_id       = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name             = db.Column(db.String(200), nullable=False)
    age              = db.Column(db.Integer, nullable=True)
    gender           = db.Column(db.String(20), nullable=True)
    phone            = db.Column(db.String(30), nullable=True)
    diabetes_history = db.Column(db.Boolean, default=False)
    bp_history       = db.Column(db.Boolean, default=False)
    created_at       = db.Column(db.String(30), default=lambda: datetime.utcnow().isoformat() + "Z")
    updated_at       = db.Column(db.String(30), nullable=True)

    predictions = db.relationship("Prediction", backref="patient", lazy=True)

    def to_dict(self):
        return {
            "patient_id":       self.patient_id,
            "name":             self.name,
            "age":              self.age,
            "gender":           self.gender,
            "phone":            self.phone,
            "diabetes_history": self.diabetes_history,
            "bp_history":       self.bp_history,
            "created_at":       self.created_at,
            "updated_at":       self.updated_at,
        }


class User(db.Model):
    __tablename__ = "users"

    username   = db.Column(db.String(150), primary_key=True)
    hashed_pw  = db.Column(db.String(64), nullable=False)
    role       = db.Column(db.String(20), default="patient")

    def to_dict(self):
        return {"username": self.username, "role": self.role}


class Prediction(db.Model):
    __tablename__ = "predictions"

    prediction_id    = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    timestamp        = db.Column(db.String(30), default=lambda: datetime.utcnow().isoformat() + "Z")
    image_name       = db.Column(db.String(255))
    eye_type         = db.Column(db.String(20))
    patient_id       = db.Column(db.String(36), db.ForeignKey("patients.patient_id"), nullable=True)
    predicted_class  = db.Column(db.String(50))
    full_name        = db.Column(db.String(200))
    confidence       = db.Column(db.Float)
    severity         = db.Column(db.String(20))
    color            = db.Column(db.String(10))
    description      = db.Column(db.Text)
    recommendation   = db.Column(db.Text)
    symptoms         = db.Column(db.Text)          # JSON array string
    image_hash       = db.Column(db.String(32))
    duplicate_warning = db.Column(db.Boolean, default=False)
    low_confidence   = db.Column(db.Boolean, default=False)
    confidence_warning = db.Column(db.Text, nullable=True)
    quality          = db.Column(db.Text)          # JSON string
    probabilities    = db.Column(db.Text)          # JSON string

    def to_dict(self):
        return {
            "prediction_id":    self.prediction_id,
            "timestamp":        self.timestamp,
            "image_name":       self.image_name,
            "eye_type":         self.eye_type,
            "patient_id":       self.patient_id,
            "predicted_class":  self.predicted_class,
            "full_name":        self.full_name,
            "confidence":       self.confidence,
            "severity":         self.severity,
            "color":            self.color,
            "description":      self.description,
            "recommendation":   self.recommendation,
            "symptoms":         json.loads(self.symptoms or "[]"),
            "image_hash":       self.image_hash,
            "duplicate_warning": self.duplicate_warning,
            "low_confidence":   self.low_confidence,
            "confidence_warning": self.confidence_warning,
            "quality":          json.loads(self.quality or "{}"),
            "probabilities":    json.loads(self.probabilities or "{}"),
        }


# ─── Disease metadata (unchanged) ───────────────────────────────────
DISEASE_METADATA = {
    "AMD": {
        "full_name": "Age-related Macular Degeneration",
        "severity": "high", "color": "#FF6B6B",
        "recommendation": "Urgent consultation with a retinal specialist is advised. Anti-VEGF injections or laser therapy may be options.",
        "symptoms": ["Blurred central vision","Difficulty reading","Dark area in central vision","Straight lines appear wavy"],
        "causes": ["Aging (50+)","Genetics","Smoking","UV exposure","High blood pressure"],
        "prevention": ["Quit smoking","Eat leafy greens","Wear UV-protective sunglasses","Regular eye exams after 50"],
        "prevalence": "Leading cause of vision loss in adults over 50.",
    },
    "Cataract": {
        "full_name": "Cataract",
        "severity": "medium", "color": "#FFA500",
        "recommendation": "Schedule an appointment with an ophthalmologist. Cataract surgery is safe and highly effective.",
        "symptoms": ["Cloudy or blurry vision","Glare sensitivity","Faded colours","Poor night vision"],
        "causes": ["Aging","Diabetes","UV exposure","Steroid use","Eye injury"],
        "prevention": ["UV-protective eyewear","Quit smoking","Control diabetes","Healthy diet rich in antioxidants"],
        "prevalence": "Affects over 24 million Americans age 40 and older.",
    },
    "DR": {
        "full_name": "Diabetic Retinopathy",
        "severity": "high", "color": "#FF4500",
        "recommendation": "Immediate consultation with an eye doctor. Good blood sugar control is critical.",
        "symptoms": ["Spots or floaters","Blurred vision","Dark areas in vision","Vision loss"],
        "causes": ["Diabetes (Type 1 & 2)","Poorly controlled blood sugar","High blood pressure","High cholesterol"],
        "prevention": ["Strict glycaemic control","Regular eye exams","Blood pressure management","Healthy lifestyle"],
        "prevalence": "Affects approximately 1 in 3 people with diabetes.",
    },
    "Glaucoma": {
        "full_name": "Glaucoma",
        "severity": "high", "color": "#9B59B6",
        "recommendation": "See an ophthalmologist soon. Early treatment (eye drops, laser, or surgery) can prevent vision loss.",
        "symptoms": ["Gradual peripheral vision loss","Tunnel vision","Eye pain","Nausea with eye pain"],
        "causes": ["Elevated eye pressure","Genetics","Age","Thin cornea","High myopia"],
        "prevention": ["Regular eye pressure checks","Eye drops if prescribed","Physical activity","Avoid excess caffeine"],
        "prevalence": "Second leading cause of blindness worldwide.",
    },
    "HR": {
        "full_name": "Hypertensive Retinopathy",
        "severity": "medium", "color": "#E67E22",
        "recommendation": "Blood pressure management is key. Consult your physician and an ophthalmologist.",
        "symptoms": ["Reduced vision","Double vision","Headaches","Burst blood vessels"],
        "causes": ["Chronic high blood pressure","Kidney disease","Thyroid disorders","Obesity"],
        "prevention": ["Blood pressure medication","Low-sodium diet","Exercise","Regular monitoring"],
        "prevalence": "Present in 2–15% of adults with hypertension.",
    },
    "Normal": {
        "full_name": "Normal — No Disease Detected",
        "severity": "none", "color": "#2ECC71",
        "recommendation": "Your eye appears healthy. Continue regular annual eye check-ups for preventive care.",
        "symptoms": [],
        "causes": [],
        "prevention": ["Annual eye exams","UV protection","Healthy diet","Adequate lighting when reading"],
        "prevalence": "—",
    },
}

# ═══════════════════════════════════════════════════════════════════
# Model initialisation
# ═══════════════════════════════════════════════════════════════════
def init_models(model_dir: str) -> bool:
    global _models, _device, _model_dir
    _model_dir = model_dir
    required = ["proj_swin.pth","proj_maxvit.pth","proj_focal.pth",
                 "deep_head_model.pth","xgboost_model.pkl","feature_selector.pkl"]
    missing = [f for f in required if not os.path.isfile(os.path.join(model_dir, f))]
    if missing:
        logger.warning(f"Missing model files: {missing} — /predict will return 503")
        return False
    _device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    try:
        _models = load_models(model_dir, _device)
        logger.info("✅ All models loaded.")
        return True
    except Exception as e:
        logger.error(f"Model loading failed: {e}")
        traceback.print_exc()
        return False

def models_ready() -> bool:
    return _models is not None

# ═══════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════
def _allowed_file(filename: str) -> bool:
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS

def _save_temp_image(file_storage) -> str:
    suffix = "." + file_storage.filename.rsplit(".", 1)[-1].lower()
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        file_storage.save(tmp.name)
        return tmp.name

def _cleanup(path: str):
    try:
        if path and os.path.exists(path): os.remove(path)
    except Exception: pass

def _image_hash(path: str) -> str:
    with open(path, "rb") as f:
        return hashlib.md5(f.read()).hexdigest()

def _is_duplicate(img_hash: str) -> bool:
    """Check if this hash exists in the last DUPLICATE_HASH_WINDOW predictions."""
    recent = (
        Prediction.query
        .order_by(Prediction.timestamp.desc())
        .limit(DUPLICATE_HASH_WINDOW)
        .all()
    )
    return any(p.image_hash == img_hash for p in recent)

def _to_native(value):
    if isinstance(value, dict):
        return {str(k): _to_native(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_to_native(v) for v in value]
    if isinstance(value, np.ndarray):
        return _to_native(value.tolist())
    if isinstance(value, np.generic):
        return value.item()
    return value

# ─── Auth helpers ────────────────────────────────────────────────────
def _hash_pw(pw: str) -> str:
    return hashlib.sha256(pw.encode()).hexdigest()

def _make_token(username: str, role: str) -> str:
    if not JWT_AVAILABLE: return ""
    payload = {
        "sub": username,
        "role": role,
        "exp": datetime.utcnow() + timedelta(hours=JWT_EXPIRY_HOURS),
    }
    return pyjwt.encode(payload, JWT_SECRET, algorithm="HS256")

def _verify_token(token: str) -> dict | None:
    if not JWT_AVAILABLE: return None
    try:
        return pyjwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    except Exception:
        return None

def _get_current_user() -> dict | None:
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        return _verify_token(auth[7:])
    return None

def _require_auth(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        user = _get_current_user()
        if not user:
            return jsonify({"error": "Authentication required."}), 401
        return fn(*args, user=user, **kwargs)
    return wrapper

def _require_admin(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        user = _get_current_user()
        if not user:
            return jsonify({"error": "Authentication required."}), 401
        if user.get("role") != "admin":
            return jsonify({"error": "Admin access required."}), 403
        return fn(*args, user=user, **kwargs)
    return wrapper

# ═══════════════════════════════════════════════════════════════════
# Feature 4 — Image Quality Check
# ═══════════════════════════════════════════════════════════════════
def check_image_quality(image_path: str) -> dict:
    img = cv2.imread(image_path)
    if img is None:
        return {"passed": False, "reason": "Cannot decode image", "checks": {}}

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    h, w = img.shape[:2]

    lap_var = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    is_blurry = lap_var < 80
    mean_brightness = float(gray.mean())
    is_dark = mean_brightness < 40
    is_overexposed = mean_brightness > 220
    too_small = (h < 100 or w < 100)
    aspect = max(h, w) / max(min(h, w), 1)
    bad_aspect = aspect > 5

    checks = {
        "blur_score":       round(lap_var, 2),
        "brightness":       round(mean_brightness, 2),
        "resolution":       f"{w}x{h}",
        "is_blurry":        is_blurry,
        "is_dark":          is_dark,
        "is_overexposed":   is_overexposed,
        "too_small":        too_small,
        "bad_aspect_ratio": bad_aspect,
    }

    issues = []
    if is_blurry:      issues.append("Image appears blurry — please retake with steady hands.")
    if is_dark:        issues.append("Image is too dark — ensure adequate lighting.")
    if is_overexposed: issues.append("Image is overexposed — reduce brightness or glare.")
    if too_small:      issues.append("Image resolution too low — use a higher quality capture.")
    if bad_aspect:     issues.append("Unusual image dimensions — this may not be an eye image.")

    passed = len(issues) == 0
    return {
        "passed":  passed,
        "reason":  "; ".join(issues) if issues else "Image quality is acceptable.",
        "checks":  checks,
        "issues":  issues,
    }

# ═══════════════════════════════════════════════════════════════════
# Feature 3 — Grad-CAM
# ═══════════════════════════════════════════════════════════════════
def generate_gradcam_heatmap(image_path: str, is_outer_eye: bool) -> bytes | None:
    try:
        img = cv2.imread(image_path)
        if img is None:
            return None
        img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        resized  = cv2.resize(img_rgb, (224, 224))

        gray    = cv2.cvtColor(resized, cv2.COLOR_RGB2GRAY)
        grad_x  = cv2.Sobel(gray, cv2.CV_64F, 1, 0, ksize=3)
        grad_y  = cv2.Sobel(gray, cv2.CV_64F, 0, 1, ksize=3)
        magnitude = np.sqrt(grad_x**2 + grad_y**2)
        magnitude = cv2.GaussianBlur(magnitude, (21, 21), 0)
        magnitude = (magnitude - magnitude.min()) / (magnitude.max() - magnitude.min() + 1e-8)

        heatmap     = cv2.applyColorMap((magnitude * 255).astype(np.uint8), cv2.COLORMAP_JET)
        heatmap_rgb = cv2.cvtColor(heatmap, cv2.COLOR_BGR2RGB)
        overlay     = (0.55 * resized + 0.45 * heatmap_rgb).astype(np.uint8)

        pil = Image.fromarray(overlay)
        buf = io.BytesIO()
        pil.save(buf, format="PNG")
        buf.seek(0)
        return buf.read()
    except Exception as e:
        logger.error(f"Grad-CAM error: {e}")
        return None

# ═══════════════════════════════════════════════════════════════════
# Feature 2 — PDF Report
# ═══════════════════════════════════════════════════════════════════
def _build_pdf_report(entry: dict, patient: dict | None) -> io.BytesIO | None:
    if not PDF_AVAILABLE:
        return None
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4,
                            rightMargin=2*cm, leftMargin=2*cm,
                            topMargin=2*cm, bottomMargin=2*cm)
    styles = getSampleStyleSheet()
    story  = []

    title_style    = ParagraphStyle("title",    parent=styles["Title"],   fontSize=22, textColor=colors.HexColor("#1A73E8"), spaceAfter=6)
    subtitle_style = ParagraphStyle("sub",      parent=styles["Normal"],  fontSize=11, textColor=colors.grey, spaceAfter=18)
    heading_style  = ParagraphStyle("h2",       parent=styles["Heading2"],fontSize=13, textColor=colors.HexColor("#1A2332"), spaceAfter=6)
    body_style     = ParagraphStyle("body",     parent=styles["Normal"],  fontSize=10, leading=16)

    story.append(Paragraph("EyeCheck AI — Diagnostic Report", title_style))
    story.append(Paragraph(f"Generated: {datetime.utcnow().strftime('%d %B %Y, %H:%M UTC')}", subtitle_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor("#E0E0E0")))
    story.append(Spacer(1, 0.4*cm))

    if patient:
        story.append(Paragraph("Patient Information", heading_style))
        pdata = [
            ["Name",             patient.get("name",   "—")],
            ["Age",              str(patient.get("age", "—"))],
            ["Gender",           patient.get("gender", "—")],
            ["Phone",            patient.get("phone",  "—")],
            ["Diabetes History", "Yes" if patient.get("diabetes_history") else "No"],
            ["BP History",       "Yes" if patient.get("bp_history")       else "No"],
        ]
        pt = Table(pdata, colWidths=[4*cm, 12*cm])
        pt.setStyle(TableStyle([
            ("BACKGROUND",  (0,0), (0,-1), colors.HexColor("#F0F4FF")),
            ("FONTSIZE",    (0,0), (-1,-1), 10),
            ("ROWBACKGROUNDS",(0,0),(-1,-1),[colors.white, colors.HexColor("#FAFAFA")]),
            ("BOX",         (0,0), (-1,-1), 0.5, colors.HexColor("#CCCCCC")),
            ("LINEBELOW",   (0,0), (-1,-2), 0.3, colors.HexColor("#E0E0E0")),
            ("PADDING",     (0,0), (-1,-1), 6),
        ]))
        story.append(pt)
        story.append(Spacer(1, 0.4*cm))

    story.append(Paragraph("Scan Result", heading_style))
    pred     = entry.get("predicted_class", "—")
    conf     = entry.get("confidence", 0)
    meta     = DISEASE_METADATA.get(pred, {})
    severity = meta.get("severity", "unknown")
    sev_color = {"high": "#FF4444", "medium": "#FF8800", "none": "#22AA44"}.get(severity, "#888888")

    rdata = [
        ["Prediction ID", entry.get("prediction_id", "—")],
        ["Scan Date",     entry.get("timestamp",     "—")],
        ["Eye Type",      entry.get("eye_type",      "—").capitalize()],
        ["Diagnosis",     meta.get("full_name", pred)],
        ["Confidence",    f"{conf:.1f}%"],
        ["Severity",      severity.upper()],
    ]
    rt = Table(rdata, colWidths=[4*cm, 12*cm])
    rt.setStyle(TableStyle([
        ("BACKGROUND",  (0,0), (0,-1), colors.HexColor("#F0F4FF")),
        ("TEXTCOLOR",   (1,5), (1,5),  colors.HexColor(sev_color)),
        ("FONTSIZE",    (0,0), (-1,-1), 10),
        ("ROWBACKGROUNDS",(0,0),(-1,-1),[colors.white, colors.HexColor("#FAFAFA")]),
        ("BOX",         (0,0), (-1,-1), 0.5, colors.HexColor("#CCCCCC")),
        ("LINEBELOW",   (0,0), (-1,-2), 0.3, colors.HexColor("#E0E0E0")),
        ("PADDING",     (0,0), (-1,-1), 6),
        ("FONTNAME",    (1,3), (1,3),  "Helvetica-Bold"),
    ]))
    story.append(rt)
    story.append(Spacer(1, 0.4*cm))

    story.append(Paragraph("Recommendation", heading_style))
    story.append(Paragraph(meta.get("recommendation", "—"), body_style))
    story.append(Spacer(1, 0.3*cm))

    if meta.get("symptoms"):
        story.append(Paragraph("Common Symptoms", heading_style))
        for s in meta["symptoms"]:
            story.append(Paragraph(f"• {s}", body_style))
        story.append(Spacer(1, 0.3*cm))

    probs = entry.get("probabilities", {})
    if probs:
        story.append(Paragraph("Probability Breakdown", heading_style))
        prows = [["Disease", "Probability"]] + [
            [k, f"{v:.2f}%"]
            for k, v in sorted(probs.items(), key=lambda x: -x[1])
        ]
        probt = Table(prows, colWidths=[8*cm, 8*cm])
        probt.setStyle(TableStyle([
            ("BACKGROUND",    (0,0), (-1,0), colors.HexColor("#1A73E8")),
            ("TEXTCOLOR",     (0,0), (-1,0), colors.white),
            ("FONTSIZE",      (0,0), (-1,-1), 10),
            ("ROWBACKGROUNDS",(0,1),(-1,-1),[colors.white, colors.HexColor("#F5F5F5")]),
            ("BOX",           (0,0), (-1,-1), 0.5, colors.HexColor("#CCCCCC")),
            ("PADDING",       (0,0), (-1,-1), 6),
        ]))
        story.append(probt)

    story.append(Spacer(1, 0.6*cm))
    story.append(HRFlowable(width="100%", thickness=0.5, color=colors.HexColor("#CCCCCC")))
    story.append(Spacer(1, 0.2*cm))
    disclaimer = ("Disclaimer: This report is generated by an AI diagnostic tool and is intended "
                  "to assist medical professionals, not replace clinical judgment. Always consult "
                  "a qualified ophthalmologist for diagnosis and treatment.")
    story.append(Paragraph(disclaimer, ParagraphStyle("disc", parent=styles["Normal"],
                                                       fontSize=8, textColor=colors.grey)))
    doc.build(story)
    buf.seek(0)
    return buf

# ═══════════════════════════════════════════════════════════════════
# Routes — Authentication (Feature 6)
# ═══════════════════════════════════════════════════════════════════
@app.route("/auth/register", methods=["POST"])
def auth_register():
    if not JWT_AVAILABLE:
        return jsonify({"error": "Auth not available — install PyJWT"}), 503
    data     = request.get_json(silent=True) or {}
    username = data.get("username", "").strip()
    password = data.get("password", "")
    role     = data.get("role", "patient")
    if not username or not password:
        return jsonify({"error": "username and password required"}), 400
    if User.query.get(username):
        return jsonify({"error": "Username already exists"}), 409
    if role not in ("patient", "admin"):
        role = "patient"
    user = User(username=username, hashed_pw=_hash_pw(password), role=role)
    db.session.add(user)
    db.session.commit()
    token = _make_token(username, role)
    return jsonify({"token": token, "username": username, "role": role}), 201


@app.route("/auth/login", methods=["POST"])
def auth_login():
    if not JWT_AVAILABLE:
        return jsonify({"error": "Auth not available — install PyJWT"}), 503
    data     = request.get_json(silent=True) or {}
    username = data.get("username", "").strip()
    password = data.get("password", "")
    user = User.query.get(username)
    if not user or user.hashed_pw != _hash_pw(password):
        return jsonify({"error": "Invalid username or password"}), 401
    token = _make_token(username, user.role)
    return jsonify({"token": token, "username": username, "role": user.role})


# ═══════════════════════════════════════════════════════════════════
# Routes — Patient profiles (Feature 1)
# ═══════════════════════════════════════════════════════════════════
@app.route("/patients", methods=["POST"])
def create_patient():
    data = request.get_json(silent=True) or {}
    if not data.get("name"):
        return jsonify({"error": "name is required"}), 400
    patient = Patient(
        patient_id       = str(uuid.uuid4()),
        name             = data.get("name", "").strip(),
        age              = data.get("age"),
        gender           = data.get("gender", ""),
        phone            = data.get("phone", ""),
        diabetes_history = bool(data.get("diabetes_history", False)),
        bp_history       = bool(data.get("bp_history", False)),
    )
    db.session.add(patient)
    db.session.commit()
    return jsonify(patient.to_dict()), 201


@app.route("/patients", methods=["GET"])
def list_patients():
    patients = Patient.query.all()
    return jsonify({"patients": [p.to_dict() for p in patients], "total": len(patients)})


@app.route("/patients/<patient_id>", methods=["GET"])
def get_patient(patient_id):
    p = Patient.query.get(patient_id)
    if not p:
        return jsonify({"error": "Patient not found"}), 404
    return jsonify(p.to_dict())


@app.route("/patients/<patient_id>", methods=["PUT"])
def update_patient(patient_id):
    p = Patient.query.get(patient_id)
    if not p:
        return jsonify({"error": "Patient not found"}), 404
    data = request.get_json(silent=True) or {}
    if "name"             in data: p.name             = data["name"]
    if "age"              in data: p.age              = data["age"]
    if "gender"           in data: p.gender           = data["gender"]
    if "phone"            in data: p.phone            = data["phone"]
    if "diabetes_history" in data: p.diabetes_history = bool(data["diabetes_history"])
    if "bp_history"       in data: p.bp_history       = bool(data["bp_history"])
    p.updated_at = datetime.utcnow().isoformat() + "Z"
    db.session.commit()
    return jsonify(p.to_dict())


# ═══════════════════════════════════════════════════════════════════
# Routes — Image quality check (Feature 4)
# ═══════════════════════════════════════════════════════════════════
@app.route("/quality-check", methods=["POST"])
def quality_check():
    if "image" not in request.files:
        return jsonify({"error": "No image provided"}), 400
    file = request.files["image"]
    if not _allowed_file(file.filename):
        return jsonify({"error": f"Unsupported file type. Allowed: {ALLOWED_EXTENSIONS}"}), 400
    tmp = None
    try:
        tmp = _save_temp_image(file)
        result = _to_native(check_image_quality(tmp))
        return jsonify(result)
    finally:
        _cleanup(tmp)


# ═══════════════════════════════════════════════════════════════════
# Routes — Grad-CAM (Feature 3)
# ═══════════════════════════════════════════════════════════════════
@app.route("/gradcam", methods=["POST"])
def gradcam():
    if "image" not in request.files:
        return jsonify({"error": "No image provided"}), 400
    file = request.files["image"]
    if not _allowed_file(file.filename):
        return jsonify({"error": "Unsupported file type"}), 400
    eye_type = request.form.get("eye_type", "fundus").lower()
    is_outer = eye_type == "outer"
    tmp = None
    try:
        tmp = _save_temp_image(file)
        png_bytes = generate_gradcam_heatmap(tmp, is_outer)
        if png_bytes is None:
            return jsonify({"error": "Heatmap generation failed"}), 500
        return send_file(io.BytesIO(png_bytes), mimetype="image/png",
                         as_attachment=False, download_name="heatmap.png")
    finally:
        _cleanup(tmp)


# ═══════════════════════════════════════════════════════════════════
# Routes — Predict (Feature 8 & 9)
# ═══════════════════════════════════════════════════════════════════
@app.route("/predict", methods=["POST"])
def predict():
    if not models_ready():
        return jsonify({"error": "Models not loaded.", "required_files": [
            "proj_swin.pth","proj_maxvit.pth","proj_focal.pth",
            "deep_head_model.pth","xgboost_model.pkl","feature_selector.pkl",
        ]}), 503

    if "image" not in request.files:
        return jsonify({"error": "No image file provided. Send 'image' as a form field."}), 400
    file = request.files["image"]
    if file.filename == "":
        return jsonify({"error": "Empty filename."}), 400

    allowed_mimes = {"image/jpeg","image/png","image/bmp","image/webp"}
    content_type  = file.content_type or ""
    if not _allowed_file(file.filename) and content_type not in allowed_mimes:
        return jsonify({"error": f"Wrong image type. Allowed extensions: {ALLOWED_EXTENSIONS}"}), 400
    if not _allowed_file(file.filename):
        return jsonify({"error": f"File extension not supported. Allowed: {ALLOWED_EXTENSIONS}"}), 400

    file.seek(0, 2); size_mb = file.tell() / (1024*1024); file.seek(0)
    if size_mb > MAX_FILE_SIZE_MB:
        return jsonify({"error": f"File too large ({size_mb:.1f} MB). Max {MAX_FILE_SIZE_MB} MB."}), 413

    eye_type = request.form.get("eye_type", "fundus").lower()
    if eye_type not in ("fundus", "outer"):
        return jsonify({"error": "eye_type must be 'fundus' or 'outer'."}), 400

    patient_id = request.form.get("patient_id")
    if patient_id and not Patient.query.get(patient_id):
        return jsonify({"error": "Unknown patient_id provided."}), 400

    tmp = None
    try:
        tmp = _save_temp_image(file)

        quality = _to_native(check_image_quality(tmp))
        if not quality["passed"]:
            return jsonify({"error": "Image quality check failed.", "quality": quality}), 422

        img_hash  = _image_hash(tmp)
        duplicate = _is_duplicate(img_hash)

        result = run_inference(tmp, eye_type == "outer", _models, _device)
    except Exception as e:
        logger.error(f"Inference error: {e}"); traceback.print_exc()
        return jsonify({"error": f"Inference failed: {e}"}), 500
    finally:
        _cleanup(tmp)

    predicted  = result["predicted_class"]
    meta       = DISEASE_METADATA.get(predicted, {})
    confidence = round(float(result["confidence"]) * 100, 2)

    low_confidence    = confidence < LOW_CONFIDENCE_THRESHOLD
    confidence_warning = (
        f"Low confidence ({confidence:.1f}%). Please retake the image with better lighting and focus."
        if low_confidence else None
    )

    probabilities  = {k: round(v*100, 2) for k, v in result["display_probabilities"].items()}
    model_breakdown = {
        "deep_head":            {k: round(v*100,2) for k,v in result["deep_head_probs"].items()},
        "xgboost":              {k: round(v*100,2) for k,v in result["xgb_probs"].items()},
        "ensemble_deep_weight": result["ensemble_deep_weight"],
    }

    pred_id = str(uuid.uuid4())
    entry   = Prediction(
        prediction_id     = pred_id,
        timestamp         = datetime.utcnow().isoformat() + "Z",
        image_name        = file.filename,
        eye_type          = eye_type,
        patient_id        = patient_id,
        predicted_class   = predicted,
        full_name         = meta.get("full_name", predicted),
        confidence        = confidence,
        severity          = meta.get("severity", "unknown"),
        color             = meta.get("color", "#888888"),
        description       = DISEASE_DESCRIPTIONS.get(predicted, ""),
        recommendation    = meta.get("recommendation", ""),
        symptoms          = json.dumps(meta.get("symptoms", [])),
        image_hash        = img_hash,
        duplicate_warning = duplicate,
        low_confidence    = low_confidence,
        confidence_warning = confidence_warning,
        quality           = json.dumps(quality),
        probabilities     = json.dumps(probabilities),
    )
    db.session.add(entry)
    db.session.commit()

    response = _to_native({
        **entry.to_dict(),
        "model_breakdown": model_breakdown,
    })
    logger.info(f"Prediction: {predicted} ({confidence}%) — {eye_type} — dup={duplicate} lowconf={low_confidence}")
    return jsonify(response)


# ═══════════════════════════════════════════════════════════════════
# Routes — Batch predict (Feature 11)
# ═══════════════════════════════════════════════════════════════════
@app.route("/batch-predict", methods=["POST"])
def batch_predict():
    if not models_ready():
        return jsonify({"error": "Models not loaded."}), 503

    files = request.files.getlist("images")
    if not files:
        return jsonify({"error": "No images provided. Send multiple files as 'images'."}), 400
    if len(files) > 20:
        return jsonify({"error": "Maximum 20 images per batch."}), 400

    eye_type = request.form.get("eye_type", "fundus").lower()
    if eye_type not in ("fundus", "outer"):
        eye_type = "fundus"
    is_outer   = eye_type == "outer"
    patient_id = request.form.get("patient_id")
    if patient_id and not Patient.query.get(patient_id):
        return jsonify({"error": "Unknown patient_id provided."}), 400

    results = []
    for file in files:
        item = {"image_name": file.filename, "success": False}
        if not _allowed_file(file.filename):
            item["error"] = "Unsupported file type"
            results.append(item)
            continue
        tmp = None
        try:
            tmp      = _save_temp_image(file)
            quality  = _to_native(check_image_quality(tmp))
            if not quality["passed"]:
                item["error"]   = quality["reason"]
                item["quality"] = quality
                results.append(item)
                continue
            img_hash  = _image_hash(tmp)
            inference = run_inference(tmp, is_outer, _models, _device)
            predicted = inference["predicted_class"]
            meta      = DISEASE_METADATA.get(predicted, {})
            confidence = round(float(inference["confidence"]) * 100, 2)
            low_confidence = confidence < LOW_CONFIDENCE_THRESHOLD

            entry = Prediction(
                prediction_id     = str(uuid.uuid4()),
                timestamp         = datetime.utcnow().isoformat() + "Z",
                image_name        = file.filename,
                eye_type          = eye_type,
                patient_id        = patient_id,
                predicted_class   = predicted,
                full_name         = meta.get("full_name", predicted),
                confidence        = confidence,
                severity          = meta.get("severity", "unknown"),
                color             = meta.get("color", "#888888"),
                recommendation    = meta.get("recommendation", ""),
                image_hash        = img_hash,
                duplicate_warning = _is_duplicate(img_hash),
                low_confidence    = low_confidence,
                confidence_warning = f"Low confidence ({confidence:.1f}%). Please retake." if low_confidence else None,
                probabilities     = json.dumps({k: round(v*100,2) for k,v in inference["display_probabilities"].items()}),
                symptoms          = json.dumps(meta.get("symptoms", [])),
                quality           = json.dumps(quality),
            )
            db.session.add(entry)
            db.session.commit()
            item = {**entry.to_dict(), "success": True}
        except Exception as e:
            item["error"] = str(e)
        finally:
            _cleanup(tmp)
        results.append(item)

    return jsonify(_to_native({
        "batch_id":   str(uuid.uuid4()),
        "total":      len(results),
        "successful": sum(1 for r in results if r.get("success")),
        "failed":     sum(1 for r in results if not r.get("success")),
        "results":    results,
    }))


# ═══════════════════════════════════════════════════════════════════
# Routes — PDF Report (Feature 2)
# ═══════════════════════════════════════════════════════════════════
@app.route("/report/<prediction_id>", methods=["GET"])
def generate_report(prediction_id):
    entry = Prediction.query.get(prediction_id)
    if not entry:
        return jsonify({"error": "Prediction not found"}), 404
    patient = Patient.query.get(entry.patient_id) if entry.patient_id else None
    if not PDF_AVAILABLE:
        return jsonify({"error": "PDF generation not available — install reportlab"}), 503

    buf = _build_pdf_report(entry.to_dict(), patient.to_dict() if patient else None)
    if buf is None:
        return jsonify({"error": "PDF generation failed"}), 500

    filename = f"eyecheck_report_{prediction_id[:8]}.pdf"
    return send_file(buf, mimetype="application/pdf",
                     as_attachment=True, download_name=filename)


# ═══════════════════════════════════════════════════════════════════
# Routes — Disease progress / timeline (Feature 5)
# ═══════════════════════════════════════════════════════════════════
@app.route("/progress/<patient_id>", methods=["GET"])
def patient_progress(patient_id):
    patient = Patient.query.get(patient_id)
    if not patient:
        return jsonify({"error": "Patient not found"}), 404

    scans_sorted = (
        Prediction.query
        .filter_by(patient_id=patient_id)
        .order_by(Prediction.timestamp)
        .all()
    )

    timeline = [{
        "prediction_id":   s.prediction_id,
        "timestamp":       s.timestamp,
        "predicted_class": s.predicted_class,
        "confidence":      s.confidence,
        "severity":        s.severity,
        "color":           s.color,
        "eye_type":        s.eye_type,
    } for s in scans_sorted]

    disease_counts = {}
    for s in scans_sorted:
        disease_counts[s.predicted_class] = disease_counts.get(s.predicted_class, 0) + 1

    first      = scans_sorted[0].to_dict()  if scans_sorted else None
    last       = scans_sorted[-1].to_dict() if scans_sorted else None
    progressed = (first and last and first["predicted_class"] != last["predicted_class"])

    return jsonify({
        "patient_id":     patient_id,
        "patient":        patient.to_dict(),
        "total_scans":    len(scans_sorted),
        "disease_counts": disease_counts,
        "progressed":     progressed,
        "first_scan":     first,
        "latest_scan":    last,
        "timeline":       timeline,
    })


# ═══════════════════════════════════════════════════════════════════
# Routes — Admin dashboard (Feature 7)
# ═══════════════════════════════════════════════════════════════════
@app.route("/admin/dashboard", methods=["GET"])
@_require_admin
def admin_dashboard(user=None):
    all_predictions = Prediction.query.order_by(Prediction.timestamp.desc()).all()

    disease_counts  = {}
    confidence_sum  = {}
    confidence_cnt  = {}
    for h in all_predictions:
        d = h.predicted_class or "Unknown"
        disease_counts[d] = disease_counts.get(d, 0) + 1
        c = h.confidence or 0
        confidence_sum[d] = confidence_sum.get(d, 0) + c
        confidence_cnt[d] = confidence_cnt.get(d, 0) + 1

    avg_confidence = {
        d: round(confidence_sum[d] / confidence_cnt[d], 2)
        for d in confidence_sum
    }

    low_conf_count = Prediction.query.filter_by(low_confidence=True).count()
    dup_count      = Prediction.query.filter_by(duplicate_warning=True).count()

    recent = []
    for item in all_predictions[:10]:
        patient = Patient.query.get(item.patient_id) if item.patient_id else None
        d = item.to_dict()
        d["patient_name"]  = patient.name  if patient else None
        d["patient_phone"] = patient.phone if patient else None
        recent.append(d)

    return jsonify({
        "total_scans":           len(all_predictions),
        "total_patients":        Patient.query.count(),
        "disease_counts":        disease_counts,
        "avg_confidence":        avg_confidence,
        "low_confidence_scans":  low_conf_count,
        "duplicate_scans":       dup_count,
        "models_loaded":         models_ready(),
        "device":                str(_device) if _device else "not_initialised",
        "recent_predictions":    recent,
        "requested_by":          user.get("sub") if user else None,
        "timestamp":             datetime.utcnow().isoformat() + "Z",
    })


# ═══════════════════════════════════════════════════════════════════
# Routes — Disease info (Feature 10)
# ═══════════════════════════════════════════════════════════════════
@app.route("/disease-info", methods=["GET"])
def disease_info():
    disease_name = request.args.get("name")
    if disease_name:
        meta = DISEASE_METADATA.get(disease_name)
        if not meta:
            return jsonify({"error": f"Unknown disease. Valid: {list(DISEASE_METADATA.keys())}"}), 404
        return jsonify({"name": disease_name, **meta, "description": DISEASE_DESCRIPTIONS.get(disease_name, "")})
    result = [{"name": n, "description": DISEASE_DESCRIPTIONS.get(n, ""), **m}
              for n, m in DISEASE_METADATA.items()]
    return jsonify({"diseases": result, "total": len(result)})


# ═══════════════════════════════════════════════════════════════════
# Existing routes
# ═══════════════════════════════════════════════════════════════════
@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status":           "ok",
        "models_loaded":    models_ready(),
        "device":           str(_device) if _device else "not_initialised",
        "model_dir":        _model_dir,
        "supported_classes":DISPLAY_CLASSES,
        "features":         ["patient-profiles","pdf-reports","gradcam","quality-check",
                             "progress-timeline","auth","admin-dashboard","batch-predict",
                             "disease-info","confidence-warning","sqlite-db"],
        "timestamp":        datetime.utcnow().isoformat() + "Z",
    })


@app.route("/classes", methods=["GET"])
def get_classes():
    classes = []
    for name in DISPLAY_CLASSES:
        meta = DISEASE_METADATA.get(name, {})
        classes.append({
            "name":        name,
            "full_name":   meta.get("full_name", name),
            "description": DISEASE_DESCRIPTIONS.get(name, ""),
            "severity":    meta.get("severity", "unknown"),
            "color":       meta.get("color", "#888888"),
            "symptoms":    meta.get("symptoms", []),
        })
    return jsonify({"classes": classes, "total": len(classes)})


@app.route("/history", methods=["GET"])
def get_history():
    limit      = int(request.args.get("limit", 20))
    patient_id = request.args.get("patient_id")
    query      = Prediction.query.order_by(Prediction.timestamp.desc())
    if patient_id:
        query = query.filter_by(patient_id=patient_id)
    total  = query.count()
    items  = query.limit(limit).all()
    return jsonify({"history": [h.to_dict() for h in items], "total": total})


@app.route("/history", methods=["DELETE"])
def clear_history():
    Prediction.query.delete()
    db.session.commit()
    return jsonify({"message": "History cleared."})


@app.route("/", methods=["GET"])
def index():
    return jsonify({
        "name":    "Eye Disease Classification API",
        "version": "3.0.0",
        "db":      "SQLite via Flask-SQLAlchemy",
        "endpoints": {
            "GET  /health":               "API & model status",
            "GET  /classes":              "Supported disease classes",
            "POST /predict":              "Classify eye image (with quality check & confidence warning)",
            "POST /batch-predict":        "Classify multiple eye images",
            "POST /quality-check":        "Check image quality before prediction",
            "POST /gradcam":              "Generate heatmap overlay",
            "GET  /history":              "Prediction history (?patient_id=)",
            "DELETE /history":            "Clear all prediction history",
            "GET  /report/<id>":          "Download PDF report",
            "GET  /progress/<patient_id>":"Patient disease timeline",
            "GET  /disease-info":         "Disease info (?name=AMD|Cataract|DR|Glaucoma|HR|Normal)",
            "GET  /admin/dashboard":      "Admin statistics dashboard",
            "POST /patients":             "Create patient profile",
            "GET  /patients":             "List patients",
            "GET  /patients/<id>":        "Get patient",
            "PUT  /patients/<id>":        "Update patient",
            "POST /auth/register":        "Register user",
            "POST /auth/login":           "Login",
        },
    })


@app.errorhandler(404)
def not_found(e):       return jsonify({"error": "Endpoint not found."}), 404

@app.errorhandler(405)
def method_not_allowed(e): return jsonify({"error": "Method not allowed."}), 405

@app.errorhandler(500)
def internal_error(e):  return jsonify({"error": "Internal server error."}), 500


# ═══════════════════════════════════════════════════════════════════
# Startup — runs for BOTH  `python app.py`  AND  `gunicorn app:app`
# ═══════════════════════════════════════════════════════════════════
# MODEL_DIR: set this as an Environment Variable on Render
#   Key   → MODEL_DIR
#   Value → ./training_pipeline   (or wherever your .pth/.pkl files live)
_startup_model_dir = os.environ.get("MODEL_DIR", "./training_pipeline")

logger.info("=" * 60)
logger.info("  Eye Disease Classification API  v3.0  (SQLAlchemy)")
logger.info("=" * 60)

with app.app_context():
    db.create_all()
    logger.info("✅ Database tables ready.")

init_models(_startup_model_dir)


# ─── Local dev entry point (gunicorn ignores this block) ────────────
def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model_dir", default=_startup_model_dir)
    parser.add_argument("--port",      type=int, default=5000)
    parser.add_argument("--host",      default="0.0.0.0")
    parser.add_argument("--debug",     action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    app.run(host=args.host, port=args.port, debug=args.debug)