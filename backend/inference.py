"""
inference.py
═══════════════════════════════════════════════════════════════════════
Eye Disease Classification — Single Image Inference

Mirrors the EXACT preprocessing, feature extraction, fusion, and
ensemble logic from train_and_test.py.

REQUIRED FILES (produced by train_and_test.py):
  ./training_pipeline/proj_swin.pth
  ./training_pipeline/proj_maxvit.pth
  ./training_pipeline/proj_focal.pth
  ./training_pipeline/deep_head_model.pth
  ./training_pipeline/xgboost_model.pkl
  ./training_pipeline/feature_selector.pkl

USAGE:
  python inference.py --image path/to/eye_image.jpg
  python inference.py --image path/to/eye_image.jpg --type outer   # cataract / outer-eye images
  python inference.py --image path/to/eye_image.jpg --type fundus  # fundus images (default)
  python inference.py --image path/to/eye_image.jpg --model_dir ./training_pipeline
═══════════════════════════════════════════════════════════════════════
"""

import os
import sys
import pickle
import json
import argparse
import warnings
warnings.filterwarnings("ignore")

import numpy as np
import cv2
import torch
import torch.nn as nn
import torch.nn.functional as F
from torchvision import transforms
from PIL import Image
from timm import create_model

# ─────────────────────────────────────────────────────────────────────
# Constants  (must match train_and_test.py exactly)
# ─────────────────────────────────────────────────────────────────────

CLASSES = ['AMD', 'Cataract', 'DR', 'Glaucoma', 'HR', 'Normal_fundus', 'Normal_outer']
DISPLAY_CLASSES = ['AMD', 'Cataract', 'DR', 'Glaucoma', 'HR', 'Normal']

IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD  = [0.229, 0.224, 0.225]

FEAT_DIM    = 256   # projected feature dim used during training
NUM_CLASSES = 7     # internal classes
DEFAULT_ENSEMBLE_DEEP_WEIGHT = 0.95

# Internal index → display index
# Normal_fundus (5) → Normal (5),  Normal_outer (6) → Normal (5)
_INT_TO_DISP = np.array([0, 1, 2, 3, 4, 5, 5], dtype=np.int64)

DISEASE_DESCRIPTIONS = {
    "AMD":      "Age-related Macular Degeneration — affects central vision.",
    "Cataract": "Cataract — clouding of the eye's natural lens.",
    "DR":       "Diabetic Retinopathy — retinal damage from diabetes.",
    "Glaucoma": "Glaucoma — optic nerve damage, often from high eye pressure.",
    "HR":       "Hypertensive Retinopathy — retinal damage from high blood pressure.",
    "Normal":   "No disease detected — eye appears healthy.",
}


# ─────────────────────────────────────────────────────────────────────
# Preprocessing  (copied verbatim from train_and_test.py)
# ─────────────────────────────────────────────────────────────────────

def apply_clahe(image: np.ndarray) -> np.ndarray:
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe   = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    l_clahe = clahe.apply(l)
    return cv2.cvtColor(cv2.merge((l_clahe, a, b)), cv2.COLOR_LAB2BGR)


def remove_noise(image: np.ndarray) -> np.ndarray:
    return cv2.GaussianBlur(image, (5, 5), 0)


def extract_fundus_roi(image: np.ndarray) -> np.ndarray:
    gray    = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (7, 7), 0)
    _, thresh = cv2.threshold(blurred, 20, 255, cv2.THRESH_BINARY)
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return image
    largest = max(contours, key=cv2.contourArea)
    mask    = np.zeros(gray.shape, np.uint8)
    cv2.drawContours(mask, [largest], -1, 255, -1)
    masked  = cv2.bitwise_and(image, image, mask=mask)
    x, y, w, h = cv2.boundingRect(largest)
    roi = masked[y:y + h, x:x + w]
    return roi if roi.size > 0 else image


def fundus_preprocess(image_path: str, target_size: int = 224) -> np.ndarray | None:
    img = cv2.imread(image_path)
    if img is None:
        return None
    img = apply_clahe(img)
    img = remove_noise(img)
    img = extract_fundus_roi(img)
    img = cv2.resize(img, (target_size, target_size))
    return cv2.cvtColor(img, cv2.COLOR_BGR2RGB)


def apply_unsharp_mask(image: np.ndarray,
                        sigma: float = 1.0, strength: float = 1.5) -> np.ndarray:
    blurred   = cv2.GaussianBlur(image, (0, 0), sigma)
    sharpened = cv2.addWeighted(image, 1 + strength, blurred, -strength, 0)
    return sharpened


def extract_outer_eye_roi(image: np.ndarray) -> np.ndarray:
    gray    = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (9, 9), 0)
    _, thresh = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    kernel  = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    closed  = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel)
    contours, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        h, w = image.shape[:2]
        m    = int(min(h, w) * 0.1)
        return image[m:h - m, m:w - m] if (h - 2 * m > 0 and w - 2 * m > 0) else image
    largest = max(contours, key=cv2.contourArea)
    x, y, w, h = cv2.boundingRect(largest)
    pad = int(min(w, h) * 0.05)
    ih, iw = image.shape[:2]
    x1, y1 = max(0, x - pad), max(0, y - pad)
    x2, y2 = min(iw, x + w + pad), min(ih, y + h + pad)
    roi = image[y1:y2, x1:x2]
    return roi if roi.size > 0 else image


def outer_eye_preprocess(image_path: str, target_size: int = 224) -> np.ndarray | None:
    img = cv2.imread(image_path)
    if img is None:
        return None
    img = apply_clahe(img)
    img = apply_unsharp_mask(img)
    img = extract_outer_eye_roi(img)
    img = cv2.resize(img, (target_size, target_size))
    return cv2.cvtColor(img, cv2.COLOR_BGR2RGB)


val_transform = transforms.Compose([
    transforms.ToTensor(),
    transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
])


def preprocess_image(image_path: str, is_outer_eye: bool) -> torch.Tensor:
    """Preprocess one image → normalised (1, 3, 224, 224) tensor."""
    if is_outer_eye:
        img_np = outer_eye_preprocess(image_path)
    else:
        img_np = fundus_preprocess(image_path)

    if img_np is None:
        raise ValueError(f"Could not read image: {image_path}")

    pil_img = Image.fromarray(img_np)
    tensor  = val_transform(pil_img)        # (3, 224, 224)
    return tensor.unsqueeze(0)              # (1, 3, 224, 224)


# ─────────────────────────────────────────────────────────────────────
# Model Architecture  (copied verbatim from train_and_test.py)
# ─────────────────────────────────────────────────────────────────────

class AttentionFusionModule(nn.Module):
    def __init__(self, feat_dim: int):
        super().__init__()
        self.gate = nn.Sequential(
            nn.Linear(feat_dim * 3, 3),
            nn.Softmax(dim=-1)
        )
        self.attn = nn.MultiheadAttention(feat_dim, num_heads=4, batch_first=True)
        self.norm = nn.LayerNorm(feat_dim)

    def forward(self, f_swin, f_maxvit, f_focal):
        stacked    = torch.stack([f_swin, f_maxvit, f_focal], dim=1)   # (B,3,D)
        att_out, _ = self.attn(stacked, stacked, stacked)
        att_out    = self.norm(att_out + stacked)                       # residual
        concat     = torch.cat([f_swin, f_maxvit, f_focal], dim=-1)    # (B,3D)
        weights    = self.gate(concat).unsqueeze(-1)                    # (B,3,1)
        return (att_out * weights).sum(dim=1)                           # (B,D)


class DeepHeadClassifier(nn.Module):
    def __init__(self, feat_dim: int = 256, num_classes: int = 7, dropout: float = 0.35):
        super().__init__()
        self.fusion    = AttentionFusionModule(feat_dim)
        self.deep_head = nn.Sequential(
            nn.LayerNorm(feat_dim),
            nn.Linear(feat_dim, 256),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(256, 128),
            nn.GELU(),
            nn.Dropout(dropout * 0.6),
            nn.Linear(128, num_classes),
        )
        self.feature_head = nn.Sequential(
            nn.LayerNorm(feat_dim),
            nn.Linear(feat_dim, 128),
            nn.GELU(),
        )

    def forward(self, f_swin, f_maxvit, f_focal):
        fused  = self.fusion(f_swin, f_maxvit, f_focal)
        logits = self.deep_head(fused)
        return logits, fused

    def get_features(self, f_swin, f_maxvit, f_focal):
        with torch.no_grad():
            fused = self.fusion(f_swin, f_maxvit, f_focal)
        return self.feature_head(fused)


# ─────────────────────────────────────────────────────────────────────
# Model Loader
# ─────────────────────────────────────────────────────────────────────

def _load_ensemble_weight(model_dir: str) -> float:
    """
    Load ensemble deep weight from training artifacts.
    Priority:
      1) xgboost_metrics.json["ensemble_deep_weight"]
      2) training_summary.json["ensemble"]["deep_weight"]
      3) default constant
    """
    metrics_path = os.path.join(model_dir, "xgboost_metrics.json")
    if os.path.isfile(metrics_path):
        try:
            with open(metrics_path, "r", encoding="utf-8") as f:
                metrics = json.load(f)
            val = float(metrics.get("ensemble_deep_weight"))
            if 0.0 <= val <= 1.0:
                return val
        except Exception:
            pass

    summary_path = os.path.join(model_dir, "training_summary.json")
    if os.path.isfile(summary_path):
        try:
            with open(summary_path, "r", encoding="utf-8") as f:
                summary = json.load(f)
            val = float(summary.get("ensemble", {}).get("deep_weight"))
            if 0.0 <= val <= 1.0:
                return val
        except Exception:
            pass

    return DEFAULT_ENSEMBLE_DEEP_WEIGHT


def load_models(model_dir: str, device: torch.device) -> dict:
    """Load all saved models and return them in a dict."""
    print(f"\n  Loading models from: {model_dir}")

    # ── Backbone + projection heads ──────────────────────────────────
    # Swin-Tiny
    swin = create_model("swin_tiny_patch4_window7_224",
                         pretrained=True, num_classes=0,
                         global_pool="avg").to(device).eval()
    proj_swin = nn.Sequential(
        nn.Linear(swin.num_features, FEAT_DIM), nn.GELU()
    ).to(device)
    proj_swin.load_state_dict(
        torch.load(os.path.join(model_dir, "proj_swin.pth"), map_location=device)
    )
    proj_swin.eval()
    print("  ✓ Swin-Tiny + projection loaded")

    # MaxViT-Tiny
    maxvit = create_model("maxvit_tiny_tf_224",
                           pretrained=True, num_classes=0,
                           global_pool="avg").to(device).eval()
    proj_maxvit = nn.Sequential(
        nn.Linear(maxvit.num_features, FEAT_DIM), nn.GELU()
    ).to(device)
    proj_maxvit.load_state_dict(
        torch.load(os.path.join(model_dir, "proj_maxvit.pth"), map_location=device)
    )
    proj_maxvit.eval()
    print("  ✓ MaxViT-Tiny + projection loaded")

    # FocalNet-Tiny
    focal = create_model("focalnet_tiny_srf",
                          pretrained=True, num_classes=0,
                          global_pool="avg").to(device).eval()
    proj_focal = nn.Sequential(
        nn.Linear(focal.num_features, FEAT_DIM), nn.GELU()
    ).to(device)
    proj_focal.load_state_dict(
        torch.load(os.path.join(model_dir, "proj_focal.pth"), map_location=device)
    )
    proj_focal.eval()
    print("  ✓ FocalNet-Tiny + projection loaded")

    # ── Deep Head ────────────────────────────────────────────────────
    deep_head = DeepHeadClassifier(
        feat_dim=FEAT_DIM, num_classes=NUM_CLASSES, dropout=0.30
    ).to(device)
    deep_head.load_state_dict(
        torch.load(os.path.join(model_dir, "deep_head_model.pth"), map_location=device)
    )
    deep_head.eval()
    print("  ✓ Deep Head (Attention Fusion) loaded")

    # ── XGBoost + feature selector ───────────────────────────────────
    with open(os.path.join(model_dir, "xgboost_model.pkl"), "rb") as f:
        xgb_model = pickle.load(f)
    with open(os.path.join(model_dir, "feature_selector.pkl"), "rb") as f:
        selector = pickle.load(f)
    print("  ✓ XGBoost model + feature selector loaded")
    deep_w = _load_ensemble_weight(model_dir)
    print(f"  ✓ Ensemble weights loaded: {deep_w:.0%} Deep + {1.0 - deep_w:.0%} XGBoost")

    return {
        "swin": swin, "proj_swin": proj_swin,
        "maxvit": maxvit, "proj_maxvit": proj_maxvit,
        "focal": focal, "proj_focal": proj_focal,
        "deep_head": deep_head,
        "xgb": xgb_model,
        "selector": selector,
        "ensemble_deep_weight": deep_w,
    }


# ─────────────────────────────────────────────────────────────────────
# Inference
# ─────────────────────────────────────────────────────────────────────

@torch.no_grad()
def run_inference(image_path: str, is_outer_eye: bool,
                  models: dict, device: torch.device) -> dict:
    """
    Full inference pipeline for a single image.

    Returns a dict with:
      - predicted_class     : display class name (one of 6)
      - confidence          : ensemble probability for the predicted class
      - display_probabilities : {class_name: prob} for all 6 display classes
      - deep_head_probs     : raw 6-class probs from deep head
      - xgb_probs           : raw 6-class probs from XGBoost
    """

    # 1 ── Preprocess ─────────────────────────────────────────────────
    img_tensor = preprocess_image(image_path, is_outer_eye).to(device)  # (1,3,224,224)

    # 2 ── Extract backbone features ──────────────────────────────────
    f_swin   = models["proj_swin"](models["swin"](img_tensor))      # (1, 256)
    f_maxvit = models["proj_maxvit"](models["maxvit"](img_tensor))  # (1, 256)
    f_focal  = models["proj_focal"](models["focal"](img_tensor))    # (1, 256)

    # 3 ── Deep Head — logits + fused features ────────────────────────
    logits, fused = models["deep_head"](f_swin, f_maxvit, f_focal)  # (1,7), (1,256)
    deep_probs_7  = F.softmax(logits, dim=-1).cpu().numpy()[0]       # (7,)

    # Fused features for XGBoost (128-dim via feature_head)
    fused_feat = models["deep_head"].get_features(
        f_swin, f_maxvit, f_focal
    ).cpu().numpy()  # (1, 128)

    # Merge 7 internal → 6 display classes for deep head
    deep_probs_disp = np.zeros(len(DISPLAY_CLASSES), dtype=np.float32)
    for i, p in enumerate(deep_probs_7):
        deep_probs_disp[_INT_TO_DISP[i]] += p   # Normal_fundus + Normal_outer → Normal

    # 4 ── XGBoost ────────────────────────────────────────────────────
    # Concatenate all features: swin(256) + maxvit(256) + focal(256) + fused(128) = 896
    xgb_feat_full = np.concatenate([
        f_swin.cpu().numpy(),
        f_maxvit.cpu().numpy(),
        f_focal.cpu().numpy(),
        fused_feat,
    ], axis=1)  # (1, 896)

    # Apply the same SelectKBest (top-384) selector used during training
    xgb_feat_sel = models["selector"].transform(xgb_feat_full)  # (1, 384)

    xgb_probs_7  = models["xgb"].predict_proba(xgb_feat_sel)[0]  # (7,)

    # Merge XGBoost 7 → 6 display classes
    xgb_probs_disp = np.zeros(len(DISPLAY_CLASSES), dtype=np.float32)
    for i, p in enumerate(xgb_probs_7):
        xgb_probs_disp[_INT_TO_DISP[i]] += p

    # 5 ── Weighted Ensemble ──────────────────────────────────────────
    deep_w  = float(models.get("ensemble_deep_weight", DEFAULT_ENSEMBLE_DEEP_WEIGHT))
    xgb_w   = 1.0 - deep_w
    ens_prob = deep_w * deep_probs_disp + xgb_w * xgb_probs_disp  # (6,)

    pred_idx   = int(ens_prob.argmax())
    pred_class = DISPLAY_CLASSES[pred_idx]
    confidence = float(ens_prob[pred_idx])

    return {
        "predicted_class":      pred_class,
        "confidence":           confidence,
        "display_probabilities": {
            cls: float(prob)
            for cls, prob in zip(DISPLAY_CLASSES, ens_prob)
        },
        "deep_head_probs": {
            cls: float(prob)
            for cls, prob in zip(DISPLAY_CLASSES, deep_probs_disp)
        },
        "xgb_probs": {
            cls: float(prob)
            for cls, prob in zip(DISPLAY_CLASSES, xgb_probs_disp)
        },
        "ensemble_deep_weight": deep_w,
    }


# ─────────────────────────────────────────────────────────────────────
# Pretty-print results
# ─────────────────────────────────────────────────────────────────────

def print_results(result: dict, image_path: str, is_outer_eye: bool) -> None:
    eye_type = "Outer-eye (cataract/slit-lamp)" if is_outer_eye else "Fundus"
    bar_width = 30

    print("\n" + "═" * 60)
    print("  EYE DISEASE CLASSIFICATION — RESULT")
    print("═" * 60)
    print(f"  Image     : {os.path.basename(image_path)}")
    print(f"  Eye type  : {eye_type}")
    print(f"\n  ┌─ PREDICTION {'─' * 43}")
    print(f"  │  Class      : {result['predicted_class']}")
    print(f"  │  Confidence : {result['confidence'] * 100:.1f}%")
    print(f"  │  Info       : {DISEASE_DESCRIPTIONS[result['predicted_class']]}")
    print(f"  └{'─' * 56}")

    deep_w = float(result.get("ensemble_deep_weight", DEFAULT_ENSEMBLE_DEEP_WEIGHT))
    xgb_w = 1.0 - deep_w
    print(f"\n  ── Ensemble Probabilities ({deep_w:.0%} Deep + {xgb_w:.0%} XGBoost) ──")
    probs = result["display_probabilities"]
    sorted_classes = sorted(probs, key=probs.get, reverse=True)
    for cls in sorted_classes:
        p       = probs[cls]
        filled  = int(p * bar_width)
        bar     = "█" * filled + "░" * (bar_width - filled)
        marker  = " ◄ PREDICTED" if cls == result["predicted_class"] else ""
        print(f"  {cls:10s} {bar}  {p * 100:5.1f}%{marker}")

    print(f"\n  ── Per-model Breakdown ──")
    print(f"  {'Class':<12} {'Deep Head':>12}  {'XGBoost':>10}")
    print(f"  {'─' * 38}")
    for cls in DISPLAY_CLASSES:
        d = result["deep_head_probs"][cls] * 100
        x = result["xgb_probs"][cls] * 100
        print(f"  {cls:<12} {d:>11.1f}%  {x:>9.1f}%")

    print("═" * 60)


# ─────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Eye Disease Classifier — single image inference"
    )
    parser.add_argument(
        "--image", required=True,
        help="Path to the input eye image (.jpg / .png / .bmp)"
    )
    parser.add_argument(
        "--type", choices=["fundus", "outer"], default="fundus",
        help=(
            "Image type:\n"
            "  fundus — retinal fundus photo (AMD, DR, Glaucoma, HR, Normal)  [default]\n"
            "  outer  — outer-eye / slit-lamp photo (Cataract, Normal)"
        )
    )
    parser.add_argument(
        "--model_dir", default="./training_pipeline",
        help="Directory containing all saved model files (default: ./training_pipeline)"
    )
    parser.add_argument(
        "--device", default=None,
        help="Force device: 'cuda' or 'cpu' (auto-detected if not specified)"
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    # Validate image path
    if not os.path.isfile(args.image):
        print(f"\n  [ERROR] Image not found: {args.image}")
        sys.exit(1)

    # Validate model directory
    required = [
        "proj_swin.pth", "proj_maxvit.pth", "proj_focal.pth",
        "deep_head_model.pth", "xgboost_model.pkl", "feature_selector.pkl",
    ]
    missing = [f for f in required if not os.path.isfile(os.path.join(args.model_dir, f))]
    if missing:
        print(f"\n  [ERROR] Missing model files in '{args.model_dir}':")
        for m in missing:
            print(f"    • {m}")
        print("\n  Run train_and_test.py first to generate these files.")
        sys.exit(1)

    # Device
    if args.device:
        device = torch.device(args.device)
    else:
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"\n  Device : {device}")

    is_outer_eye = (args.type == "outer")

    # Load models
    models = load_models(args.model_dir, device)

    # Run inference
    print(f"\n  Running inference on: {args.image}")
    result = run_inference(args.image, is_outer_eye, models, device)

    # Display results
    print_results(result, args.image, is_outer_eye)


if __name__ == "__main__":
    main()