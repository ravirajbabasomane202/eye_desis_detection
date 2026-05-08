# 👁️ EyeCheck AI — Eye Disease Detection App

AI-powered eye disease detection using your trained ensemble model (Swin + MaxViT + FocalNet + XGBoost).

---

## 🏗️ Architecture

```
eye_disease_app/
├── backend/              Flask REST API
│   ├── app.py            Main API server
│   ├── inference.py      Your original inference code
│   └── requirements.txt
│
└── flutter_app/          Flutter mobile app
    ├── lib/
    │   ├── main.dart
    │   ├── screens/
    │   │   ├── home_screen.dart
    │   │   ├── scan_screen.dart
    │   │   ├── result_screen.dart
    │   │   ├── history_screen.dart
    │   │   └── settings_screen.dart
    │   ├── models/
    │   │   ├── prediction_result.dart
    │   │   └── app_state.dart
    │   └── services/
    │       └── api_service.dart
    └── pubspec.yaml
```

---

## ⚙️ Backend Setup

### 1. Install dependencies

```bash
cd backend
pip install -r requirements.txt
```

### 2. Place your trained model files

```
backend/
└── training_pipeline/
    ├── proj_swin.pth
    ├── proj_maxvit.pth
    ├── proj_focal.pth
    ├── deep_head_model.pth
    ├── xgboost_model.pkl
    └── feature_selector.pkl
```

### 3. Start the server

```bash
python app.py
# or with custom options:
python app.py --model_dir ./training_pipeline --port 5000 --host 0.0.0.0
```

### 4. Test the API

```bash
# Health check
curl http://localhost:5000/health

# Predict (fundus image)
curl -X POST http://localhost:5000/predict \
  -F "image=@/path/to/eye.jpg" \
  -F "eye_type=fundus"

# Predict (outer eye / cataract)
curl -X POST http://localhost:5000/predict \
  -F "image=@/path/to/cataract.jpg" \
  -F "eye_type=outer"
```

### Docker (optional)

```bash
docker build -t eyecheck-api .
docker run -p 5000:5000 \
  -v /path/to/your/training_pipeline:/app/training_pipeline \
  eyecheck-api
```

---

## 📱 Flutter App Setup

### 1. Install Flutter SDK

Download from https://flutter.dev/docs/get-started/install

### 2. Get dependencies

```bash
cd flutter_app
flutter pub get
```

### 3. Configure API URL

- Open the app → go to **Settings** tab
- Enter your backend URL:
  - Android Emulator: `http://10.0.2.2:5000`
  - Real device: `http://192.168.1.YOUR_IP:5000`
  - Production: `https://your-domain.com`
- Press **Test** to verify connection
- Press **Save**

### 4. Run the app

```bash
# Android emulator / device
flutter run

# iOS simulator
flutter run -d ios

# Build APK
flutter build apk --release
```

---

## 🔬 API Reference

### `POST /predict`

| Field    | Type   | Required | Description                     |
|----------|--------|----------|---------------------------------|
| image    | File   | ✅        | Eye image (jpg/png/bmp, max 20MB)|
| eye_type | string | ❌        | `fundus` (default) or `outer`   |

**Response:**
```json
{
  "prediction_id": "uuid",
  "predicted_class": "AMD",
  "full_name": "Age-related Macular Degeneration",
  "confidence": 87.3,
  "severity": "high",
  "color": "#FF6B6B",
  "description": "...",
  "recommendation": "...",
  "symptoms": ["Blurred central vision", "..."],
  "probabilities": {
    "AMD": 87.3,
    "Cataract": 2.1,
    "DR": 4.5,
    "Glaucoma": 1.8,
    "HR": 0.9,
    "Normal": 3.4
  },
  "model_breakdown": {
    "deep_head": { ... },
    "xgboost": { ... },
    "ensemble_deep_weight": 0.95
  }
}
```

---

## 🩺 Supported Conditions

| Code     | Full Name                     | Image Type | Severity |
|----------|-------------------------------|------------|----------|
| AMD      | Age-related Macular Degeneration | Fundus    | High     |
| Cataract | Cataract                      | Outer Eye  | Medium   |
| DR       | Diabetic Retinopathy          | Fundus     | High     |
| Glaucoma | Glaucoma                      | Fundus     | High     |
| HR       | Hypertensive Retinopathy      | Fundus     | Medium   |
| Normal   | Normal — Healthy Eye          | Both       | None     |

---

## ⚠️ Medical Disclaimer

This tool is for **educational and screening purposes only**. It is NOT a substitute for professional medical advice. Always consult a qualified ophthalmologist for diagnosis and treatment.