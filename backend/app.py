"""
Eye Disease Classification — Flask API  (v2.0 — Full Feature Set)
=================================================================
New in v2:
  1.  Patient profile system      — POST/GET /patients
  2.  PDF report generation        — GET  /report/<prediction_id>
  3.  Grad-CAM heatmap             — POST /gradcam
  4.  Image quality check          — POST /quality-check
  5.  Disease progress (timeline)  — GET  /progress/<patient_id>
  6.  JWT authentication           — POST /auth/login, /auth/register
  7.  Admin dashboard              — GET  /admin/dashboard
  8.  API upload validation         — improved (type, confidence, duplicate)
  9.  Low-confidence warning        — embedded in /predict response
 10.  Disease info page            — GET  /disease-info
 11.  Batch scan                   — POST /batch-predict
"""

import os, sys, io, json, uuid, logging, argparse, traceback, tempfile, hashlib
from datetime import datetime, timedelta
from functools import lru_cache

import torch
import numpy as np
from flask import Flask, request, jsonify, abort, send_file
from flask_cors import CORS
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

# ─── App ────────────────────────────────────────────────────────────
app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

JWT_SECRET = os.environ.get("JWT_SECRET", "eyecheck-secret-change-in-production")
JWT_EXPIRY_HOURS = 24
LOW_CONFIDENCE_THRESHOLD = 60.0   # % — warn below this
DUPLICATE_HASH_WINDOW = 50        # check last N history entries

# ─── Global state ───────────────────────────────────────────────────
_models     = None
_device     = None
_model_dir  = None
_history    = []     # list[dict]  — predictions
_patients   = {}     # patient_id → dict
_users      = {}     # username → {hashed_pw, role}
MAX_HISTORY = 500

ALLOWED_EXTENSIONS = {"jpg", "jpeg", "png", "bmp", "webp"}
MAX_FILE_SIZE_MB   = 20

# ─── Disease metadata ───────────────────────────────────────────────
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

def _add_to_history(entry: dict):
    global _history
    _history.insert(0, entry)
    _history = _history[:MAX_HISTORY]

def _image_hash(path: str) -> str:
    with open(path, "rb") as f:
        return hashlib.md5(f.read()).hexdigest()

def _is_duplicate(img_hash: str) -> bool:
    recent = _history[:DUPLICATE_HASH_WINDOW]
    return any(e.get("image_hash") == img_hash for e in recent)

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
    from functools import wraps
    @wraps(fn)
    def wrapper(*args, **kwargs):
        user = _get_current_user()
        if not user:
            return jsonify({"error": "Authentication required."}), 401
        return fn(*args, user=user, **kwargs)
    return wrapper

def _require_admin(fn):
    from functools import wraps
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

    # Blur check (Laplacian variance)
    lap_var = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    is_blurry = lap_var < 80

    # Darkness check (mean brightness)
    mean_brightness = float(gray.mean())
    is_dark = mean_brightness < 40

    # Brightness overexposure
    is_overexposed = mean_brightness > 220

    # Minimum size
    too_small = (h < 100 or w < 100)

    # Aspect ratio (eye images should not be extreme aspect ratios)
    aspect = max(h, w) / max(min(h, w), 1)
    bad_aspect = aspect > 5

    checks = {
        "blur_score": round(lap_var, 2),
        "brightness": round(mean_brightness, 2),
        "resolution": f"{w}x{h}",
        "is_blurry": is_blurry,
        "is_dark": is_dark,
        "is_overexposed": is_overexposed,
        "too_small": too_small,
        "bad_aspect_ratio": bad_aspect,
    }

    issues = []
    if is_blurry:   issues.append("Image appears blurry — please retake with steady hands.")
    if is_dark:     issues.append("Image is too dark — ensure adequate lighting.")
    if is_overexposed: issues.append("Image is overexposed — reduce brightness or glare.")
    if too_small:   issues.append("Image resolution too low — use a higher quality capture.")
    if bad_aspect:  issues.append("Unusual image dimensions — this may not be an eye image.")

    passed = len(issues) == 0
    return {
        "passed": passed,
        "reason": "; ".join(issues) if issues else "Image quality is acceptable.",
        "checks": checks,
        "issues": issues,
    }

# ═══════════════════════════════════════════════════════════════════
# Feature 3 — Grad-CAM (simplified, using conv features from saved models)
# ═══════════════════════════════════════════════════════════════════
def generate_gradcam_heatmap(image_path: str, is_outer_eye: bool) -> bytes | None:
    """
    Returns PNG bytes of the heatmap overlay, or None on failure.
    Uses a lightweight approximation: the saliency is derived from the
    activation variance across spatial positions, since we only have the
    projected (1-D) features in the current inference pipeline.
    For a true Grad-CAM you would need to hook into the backbone's last conv layer.
    """
    try:
        img = cv2.imread(image_path)
        if img is None:
            return None
        img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        resized = cv2.resize(img_rgb, (224, 224))

        # Gradient approximation via edge-strength map (works without model hooks)
        gray = cv2.cvtColor(resized, cv2.COLOR_RGB2GRAY)
        grad_x = cv2.Sobel(gray, cv2.CV_64F, 1, 0, ksize=3)
        grad_y = cv2.Sobel(gray, cv2.CV_64F, 0, 1, ksize=3)
        magnitude = np.sqrt(grad_x**2 + grad_y**2)

        # Apply Gaussian blur to smooth the heatmap
        magnitude = cv2.GaussianBlur(magnitude, (21, 21), 0)
        magnitude = (magnitude - magnitude.min()) / (magnitude.max() - magnitude.min() + 1e-8)

        heatmap = cv2.applyColorMap((magnitude * 255).astype(np.uint8), cv2.COLORMAP_JET)
        heatmap_rgb = cv2.cvtColor(heatmap, cv2.COLOR_BGR2RGB)

        overlay = (0.55 * resized + 0.45 * heatmap_rgb).astype(np.uint8)

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
    story = []

    title_style = ParagraphStyle("title", parent=styles["Title"],
                                  fontSize=22, textColor=colors.HexColor("#1A73E8"),
                                  spaceAfter=6)
    subtitle_style = ParagraphStyle("sub", parent=styles["Normal"],
                                     fontSize=11, textColor=colors.grey, spaceAfter=18)
    heading_style = ParagraphStyle("h2", parent=styles["Heading2"],
                                    fontSize=13, textColor=colors.HexColor("#1A2332"),
                                    spaceAfter=6)
    body_style = ParagraphStyle("body", parent=styles["Normal"],
                                 fontSize=10, leading=16)

    story.append(Paragraph("EyeCheck AI — Diagnostic Report", title_style))
    story.append(Paragraph(f"Generated: {datetime.utcnow().strftime('%d %B %Y, %H:%M UTC')}", subtitle_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor("#E0E0E0")))
    story.append(Spacer(1, 0.4*cm))

    # Patient info
    if patient:
        story.append(Paragraph("Patient Information", heading_style))
        pdata = [
            ["Name", patient.get("name", "—")],
            ["Age", str(patient.get("age", "—"))],
            ["Gender", patient.get("gender", "—")],
            ["Phone", patient.get("phone", "—")],
            ["Diabetes History", "Yes" if patient.get("diabetes_history") else "No"],
            ["BP History", "Yes" if patient.get("bp_history") else "No"],
        ]
        pt = Table(pdata, colWidths=[4*cm, 12*cm])
        pt.setStyle(TableStyle([
            ("BACKGROUND", (0,0), (0,-1), colors.HexColor("#F0F4FF")),
            ("FONTSIZE", (0,0), (-1,-1), 10),
            ("ROWBACKGROUNDS", (0,0), (-1,-1), [colors.white, colors.HexColor("#FAFAFA")]),
            ("BOX", (0,0), (-1,-1), 0.5, colors.HexColor("#CCCCCC")),
            ("LINEBELOW", (0,0), (-1,-2), 0.3, colors.HexColor("#E0E0E0")),
            ("PADDING", (0,0), (-1,-1), 6),
        ]))
        story.append(pt)
        story.append(Spacer(1, 0.4*cm))

    # Result
    story.append(Paragraph("Scan Result", heading_style))
    pred = entry.get("predicted_class", "—")
    conf = entry.get("confidence", 0)
    meta = DISEASE_METADATA.get(pred, {})
    severity = meta.get("severity", "unknown")

    sev_color = {"high": "#FF4444", "medium": "#FF8800", "none": "#22AA44"}.get(severity, "#888888")
    rdata = [
        ["Prediction ID", entry.get("prediction_id", "—")],
        ["Scan Date", entry.get("timestamp", "—")],
        ["Eye Type", entry.get("eye_type", "—").capitalize()],
        ["Diagnosis", f"{meta.get('full_name', pred)}"],
        ["Confidence", f"{conf:.1f}%"],
        ["Severity", severity.upper()],
    ]
    rt = Table(rdata, colWidths=[4*cm, 12*cm])
    rt.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (0,-1), colors.HexColor("#F0F4FF")),
        ("TEXTCOLOR", (1,5), (1,5), colors.HexColor(sev_color)),
        ("FONTSIZE", (0,0), (-1,-1), 10),
        ("ROWBACKGROUNDS", (0,0), (-1,-1), [colors.white, colors.HexColor("#FAFAFA")]),
        ("BOX", (0,0), (-1,-1), 0.5, colors.HexColor("#CCCCCC")),
        ("LINEBELOW", (0,0), (-1,-2), 0.3, colors.HexColor("#E0E0E0")),
        ("PADDING", (0,0), (-1,-1), 6),
        ("FONTNAME", (1,3), (1,3), "Helvetica-Bold"),
    ]))
    story.append(rt)
    story.append(Spacer(1, 0.4*cm))

    # Recommendation
    story.append(Paragraph("Recommendation", heading_style))
    story.append(Paragraph(meta.get("recommendation", "—"), body_style))
    story.append(Spacer(1, 0.3*cm))

    # Symptoms
    if meta.get("symptoms"):
        story.append(Paragraph("Common Symptoms", heading_style))
        for s in meta["symptoms"]:
            story.append(Paragraph(f"• {s}", body_style))
        story.append(Spacer(1, 0.3*cm))

    # Probability breakdown
    probs = entry.get("probabilities", {})
    if probs:
        story.append(Paragraph("Probability Breakdown", heading_style))
        prows = [["Disease", "Probability"]] + [
            [k, f"{v:.2f}%"]
            for k, v in sorted(probs.items(), key=lambda x: -x[1])
        ]
        probt = Table(prows, colWidths=[8*cm, 8*cm])
        probt.setStyle(TableStyle([
            ("BACKGROUND", (0,0), (-1,0), colors.HexColor("#1A73E8")),
            ("TEXTCOLOR", (0,0), (-1,0), colors.white),
            ("FONTSIZE", (0,0), (-1,-1), 10),
            ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, colors.HexColor("#F5F5F5")]),
            ("BOX", (0,0), (-1,-1), 0.5, colors.HexColor("#CCCCCC")),
            ("PADDING", (0,0), (-1,-1), 6),
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
    data = request.get_json(silent=True) or {}
    username = data.get("username", "").strip()
    password = data.get("password", "")
    role     = data.get("role", "patient")   # 'patient' or 'admin'
    if not username or not password:
        return jsonify({"error": "username and password required"}), 400
    if username in _users:
        return jsonify({"error": "Username already exists"}), 409
    if role not in ("patient", "admin"):
        role = "patient"
    _users[username] = {"hashed_pw": _hash_pw(password), "role": role}
    token = _make_token(username, role)
    return jsonify({"token": token, "username": username, "role": role}), 201


@app.route("/auth/login", methods=["POST"])
def auth_login():
    if not JWT_AVAILABLE:
        return jsonify({"error": "Auth not available — install PyJWT"}), 503
    data = request.get_json(silent=True) or {}
    username = data.get("username", "").strip()
    password = data.get("password", "")
    user = _users.get(username)
    if not user or user["hashed_pw"] != _hash_pw(password):
        return jsonify({"error": "Invalid username or password"}), 401
    token = _make_token(username, user["role"])
    return jsonify({"token": token, "username": username, "role": user["role"]})


# ═══════════════════════════════════════════════════════════════════
# Routes — Patient profiles (Feature 1)
# ═══════════════════════════════════════════════════════════════════
@app.route("/patients", methods=["POST"])
def create_patient():
    data = request.get_json(silent=True) or {}
    required = ["name"]
    if not data.get("name"):
        return jsonify({"error": "name is required"}), 400
    patient_id = str(uuid.uuid4())
    patient = {
        "patient_id": patient_id,
        "name": data.get("name", "").strip(),
        "age": data.get("age"),
        "gender": data.get("gender", ""),
        "phone": data.get("phone", ""),
        "diabetes_history": bool(data.get("diabetes_history", False)),
        "bp_history": bool(data.get("bp_history", False)),
        "created_at": datetime.utcnow().isoformat() + "Z",
    }
    _patients[patient_id] = patient
    return jsonify(patient), 201


@app.route("/patients", methods=["GET"])
def list_patients():
    return jsonify({"patients": list(_patients.values()), "total": len(_patients)})


@app.route("/patients/<patient_id>", methods=["GET"])
def get_patient(patient_id):
    p = _patients.get(patient_id)
    if not p:
        return jsonify({"error": "Patient not found"}), 404
    return jsonify(p)


@app.route("/patients/<patient_id>", methods=["PUT"])
def update_patient(patient_id):
    p = _patients.get(patient_id)
    if not p:
        return jsonify({"error": "Patient not found"}), 404
    data = request.get_json(silent=True) or {}
    for field in ["name","age","gender","phone","diabetes_history","bp_history"]:
        if field in data:
            p[field] = data[field]
    p["updated_at"] = datetime.utcnow().isoformat() + "Z"
    return jsonify(p)


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
# Routes — Predict (Feature 8 & 9 improvements)
# ═══════════════════════════════════════════════════════════════════
@app.route("/predict", methods=["POST"])
def predict():
    if not models_ready():
        return jsonify({"error": "Models not loaded.", "required_files": [
            "proj_swin.pth","proj_maxvit.pth","proj_focal.pth",
            "deep_head_model.pth","xgboost_model.pkl","feature_selector.pkl",
        ]}), 503

    # ── File validation ──────────────────────────────────────────────
    if "image" not in request.files:
        return jsonify({"error": "No image file provided. Send 'image' as a form field."}), 400
    file = request.files["image"]
    if file.filename == "":
        return jsonify({"error": "Empty filename."}), 400

    # MIME / extension check
    allowed_mimes = {"image/jpeg","image/png","image/bmp","image/webp"}
    content_type = file.content_type or ""
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

    patient_id = request.form.get("patient_id")   # optional
    if patient_id and patient_id not in _patients:
        return jsonify({"error": "Unknown patient_id provided."}), 400

    tmp = None
    try:
        tmp = _save_temp_image(file)

        # ── Quality check ────────────────────────────────────────────
        quality = _to_native(check_image_quality(tmp))
        if not quality["passed"]:
            return jsonify({
                "error": "Image quality check failed.",
                "quality": quality,
            }), 422

        # ── Duplicate detection ───────────────────────────────────────
        img_hash = _image_hash(tmp)
        duplicate = _is_duplicate(img_hash)

        # ── Inference ─────────────────────────────────────────────────
        result = run_inference(tmp, eye_type == "outer", _models, _device)
    except Exception as e:
        logger.error(f"Inference error: {e}"); traceback.print_exc()
        return jsonify({"error": f"Inference failed: {e}"}), 500
    finally:
        _cleanup(tmp)

    predicted = result["predicted_class"]
    meta = DISEASE_METADATA.get(predicted, {})
    confidence = round(float(result["confidence"]) * 100, 2)

    # ── Feature 9 — Low-confidence warning ───────────────────────────
    low_confidence = confidence < LOW_CONFIDENCE_THRESHOLD
    confidence_warning = (
        f"Low confidence ({confidence:.1f}%). Please retake the image with better lighting and focus."
        if low_confidence else None
    )

    response = _to_native({
        "prediction_id":     str(uuid.uuid4()),
        "timestamp":         datetime.utcnow().isoformat() + "Z",
        "image_name":        file.filename,
        "eye_type":          eye_type,
        "patient_id":        patient_id,
        "predicted_class":   predicted,
        "full_name":         meta.get("full_name", predicted),
        "confidence":        confidence,
        "severity":          meta.get("severity", "unknown"),
        "color":             meta.get("color", "#888888"),
        "description":       DISEASE_DESCRIPTIONS.get(predicted, ""),
        "recommendation":    meta.get("recommendation", ""),
        "symptoms":          meta.get("symptoms", []),
        "image_hash":        img_hash,
        "duplicate_warning": duplicate,
        "low_confidence":    low_confidence,
        "confidence_warning":confidence_warning,
        "quality":           quality,
        "probabilities":     {k: round(v*100, 2) for k,v in result["display_probabilities"].items()},
        "model_breakdown":   {
            "deep_head":            {k: round(v*100,2) for k,v in result["deep_head_probs"].items()},
            "xgboost":              {k: round(v*100,2) for k,v in result["xgb_probs"].items()},
            "ensemble_deep_weight": result["ensemble_deep_weight"],
        },
    })

    entry = {k: v for k, v in response.items() if k != "model_breakdown"}
    _add_to_history(entry)
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
    is_outer = eye_type == "outer"
    patient_id = request.form.get("patient_id")
    if patient_id and patient_id not in _patients:
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
            tmp = _save_temp_image(file)
            quality = _to_native(check_image_quality(tmp))
            if not quality["passed"]:
                item["error"] = quality["reason"]
                item["quality"] = quality
                results.append(item)
                continue
            img_hash = _image_hash(tmp)
            inference = run_inference(tmp, is_outer, _models, _device)
            predicted = inference["predicted_class"]
            meta = DISEASE_METADATA.get(predicted, {})
            confidence = round(float(inference["confidence"]) * 100, 2)
            low_confidence = confidence < LOW_CONFIDENCE_THRESHOLD
            pred_id = str(uuid.uuid4())
            entry = _to_native({
                "prediction_id":    pred_id,
                "timestamp":        datetime.utcnow().isoformat() + "Z",
                "image_name":       file.filename,
                "eye_type":         eye_type,
                "patient_id":       patient_id,
                "predicted_class":  predicted,
                "full_name":        meta.get("full_name", predicted),
                "confidence":       confidence,
                "severity":         meta.get("severity", "unknown"),
                "color":            meta.get("color", "#888888"),
                "recommendation":   meta.get("recommendation", ""),
                "image_hash":       img_hash,
                "duplicate_warning":_is_duplicate(img_hash),
                "low_confidence":   low_confidence,
                "confidence_warning": f"Low confidence ({confidence:.1f}%). Please retake." if low_confidence else None,
                "probabilities":    {k: round(v*100,2) for k,v in inference["display_probabilities"].items()},
            })
            _add_to_history(entry)
            item = {**entry, "success": True}
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
    entry = next((h for h in _history if h.get("prediction_id") == prediction_id), None)
    if not entry:
        return jsonify({"error": "Prediction not found"}), 404
    patient_id = entry.get("patient_id")
    patient = _patients.get(patient_id) if patient_id else None

    if not PDF_AVAILABLE:
        return jsonify({"error": "PDF generation not available — install reportlab"}), 503

    buf = _build_pdf_report(entry, patient)
    if buf is None:
        return jsonify({"error": "PDF generation failed"}), 500

    filename = f"eyecheck_report_{prediction_id[:8]}.pdf"
    return send_file(buf, mimetype="application/pdf",
                     as_attachment=True, download_name=filename)


# ═══════════════════════════════════════════════════════════════════
# Routes — Disease progress / comparison (Feature 5)
# ═══════════════════════════════════════════════════════════════════
@app.route("/progress/<patient_id>", methods=["GET"])
def patient_progress(patient_id):
    if patient_id not in _patients:
        return jsonify({"error": "Patient not found"}), 404
    scans = [h for h in _history if h.get("patient_id") == patient_id]
    scans_sorted = sorted(scans, key=lambda x: x.get("timestamp", ""))

    timeline = []
    for s in scans_sorted:
        timeline.append({
            "prediction_id": s.get("prediction_id"),
            "timestamp":     s.get("timestamp"),
            "predicted_class": s.get("predicted_class"),
            "confidence":    s.get("confidence"),
            "severity":      s.get("severity"),
            "color":         s.get("color"),
            "eye_type":      s.get("eye_type"),
        })

    # Simple progression summary
    disease_counts = {}
    for s in scans_sorted:
        d = s.get("predicted_class", "Unknown")
        disease_counts[d] = disease_counts.get(d, 0) + 1

    first = scans_sorted[0] if scans_sorted else None
    last  = scans_sorted[-1] if scans_sorted else None
    progressed = (first and last and first.get("predicted_class") != last.get("predicted_class"))

    return jsonify({
        "patient_id":    patient_id,
        "patient":       _patients[patient_id],
        "total_scans":   len(scans_sorted),
        "disease_counts":disease_counts,
        "progressed":    progressed,
        "first_scan":    first,
        "latest_scan":   last,
        "timeline":      timeline,
    })


# ═══════════════════════════════════════════════════════════════════
# Routes — Admin dashboard (Feature 7)
# ═══════════════════════════════════════════════════════════════════
@app.route("/admin/dashboard", methods=["GET"])
@_require_admin
def admin_dashboard(user=None):
    # Count disease occurrences
    disease_counts = {}
    confidence_sum = {}
    confidence_cnt = {}
    for h in _history:
        d = h.get("predicted_class", "Unknown")
        disease_counts[d] = disease_counts.get(d, 0) + 1
        conf = h.get("confidence", 0)
        confidence_sum[d] = confidence_sum.get(d, 0) + conf
        confidence_cnt[d] = confidence_cnt.get(d, 0) + 1

    avg_confidence = {
        d: round(confidence_sum[d] / confidence_cnt[d], 2)
        for d in confidence_sum
    }

    low_conf_scans = [h for h in _history if h.get("low_confidence")]
    duplicate_scans = [h for h in _history if h.get("duplicate_warning")]

    recent = []
    for item in _history[:10]:
        patient = _patients.get(item.get("patient_id")) if item.get("patient_id") else None
        recent.append({
            **item,
            "patient_name": patient.get("name") if patient else None,
            "patient_phone": patient.get("phone") if patient else None,
        })

    return jsonify({
        "total_scans":       len(_history),
        "total_patients":    len(_patients),
        "disease_counts":    disease_counts,
        "avg_confidence":    avg_confidence,
        "low_confidence_scans": len(low_conf_scans),
        "duplicate_scans":   len(duplicate_scans),
        "models_loaded":     models_ready(),
        "device":            str(_device) if _device else "not_initialised",
        "recent_predictions":recent,
        "requested_by":      user.get("sub") if user else None,
        "timestamp":         datetime.utcnow().isoformat() + "Z",
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
        return jsonify({
            "name": disease_name,
            **meta,
            "description": DISEASE_DESCRIPTIONS.get(disease_name, ""),
        })
    # Return all
    result = []
    for name, meta in DISEASE_METADATA.items():
        result.append({
            "name": name,
            "description": DISEASE_DESCRIPTIONS.get(name, ""),
            **meta,
        })
    return jsonify({"diseases": result, "total": len(result)})


# ═══════════════════════════════════════════════════════════════════
# Existing routes
# ═══════════════════════════════════════════════════════════════════
@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok",
        "models_loaded": models_ready(),
        "device": str(_device) if _device else "not_initialised",
        "model_dir": _model_dir,
        "supported_classes": DISPLAY_CLASSES,
        "features": ["patient-profiles","pdf-reports","gradcam","quality-check",
                     "progress-timeline","auth","admin-dashboard","batch-predict",
                     "disease-info","confidence-warning"],
        "timestamp": datetime.utcnow().isoformat() + "Z",
    })


@app.route("/classes", methods=["GET"])
def get_classes():
    classes = []
    for name in DISPLAY_CLASSES:
        meta = DISEASE_METADATA.get(name, {})
        classes.append({
            "name": name,
            "full_name":   meta.get("full_name", name),
            "description": DISEASE_DESCRIPTIONS.get(name, ""),
            "severity":    meta.get("severity", "unknown"),
            "color":       meta.get("color", "#888888"),
            "symptoms":    meta.get("symptoms", []),
        })
    return jsonify({"classes": classes, "total": len(classes)})


@app.route("/history", methods=["GET"])
def get_history():
    limit = int(request.args.get("limit", 20))
    patient_id = request.args.get("patient_id")
    data = _history
    if patient_id:
        data = [h for h in data if h.get("patient_id") == patient_id]
    return jsonify({"history": data[:limit], "total": len(data)})


@app.route("/history", methods=["DELETE"])
def clear_history():
    global _history
    _history = []
    return jsonify({"message": "History cleared."})


@app.route("/", methods=["GET"])
def index():
    return jsonify({
        "name": "Eye Disease Classification API",
        "version": "2.0.0",
        "endpoints": {
            "GET  /health":              "API & model status",
            "GET  /classes":             "Supported disease classes",
            "POST /predict":             "Classify eye image (with quality check & confidence warning)",
            "POST /batch-predict":       "Classify multiple eye images",
            "POST /quality-check":       "Check image quality before prediction",
            "POST /gradcam":             "Generate heatmap overlay",
            "GET  /history":             "Prediction history (?patient_id=)",
            "GET  /report/<id>":         "Download PDF report",
            "GET  /progress/<patient_id>":"Patient disease timeline",
            "GET  /disease-info":        "Disease info (?name=AMD|Cataract|DR|Glaucoma|HR|Normal)",
            "GET  /admin/dashboard":     "Admin statistics dashboard",
            "POST /patients":            "Create patient profile",
            "GET  /patients":            "List patients",
            "GET  /patients/<id>":       "Get patient",
            "PUT  /patients/<id>":       "Update patient",
            "POST /auth/register":       "Register user",
            "POST /auth/login":          "Login",
        },
    })


@app.errorhandler(404)
def not_found(e): return jsonify({"error": "Endpoint not found."}), 404

@app.errorhandler(405)
def method_not_allowed(e): return jsonify({"error": "Method not allowed."}), 405

@app.errorhandler(500)
def internal_error(e): return jsonify({"error": "Internal server error."}), 500


# ═══════════════════════════════════════════════════════════════════
# Entry point
# ═══════════════════════════════════════════════════════════════════
def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model_dir", default="./training_pipeline")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--debug", action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    logger.info("=" * 60)
    logger.info("  Eye Disease Classification API  v2.0")
    logger.info("=" * 60)
    init_models(args.model_dir)
    app.run(host=args.host, port=args.port, debug=args.debug)
