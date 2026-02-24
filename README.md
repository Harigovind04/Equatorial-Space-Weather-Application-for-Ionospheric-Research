# ESWAR 🛰️
**Equatorial Space Weather Application for Ionospheric Research**

![Flutter](https://img.shields.io/badge/Client-Flutter-blue.svg)
![Edge ML](https://img.shields.io/badge/Model-TFLite-orange.svg)
![Database](https://img.shields.io/badge/Realtime-Firebase-yellow.svg)
![Data](https://img.shields.io/badge/Data-ISRO_&_NASA-success.svg)
![Award](https://img.shields.io/badge/Award-NASA_Space_Apps_Winner-purple.svg)

## 🏆 Recognition & Impact
* **Winner:** Out of the Box Solution Award (College Category) - NASA Space Apps Challenge Kochi 2024
* **Winner:** Dr. Siby Mathew Endowment Intercollege Project Presentation 2025

## Overview
ESWAR is an award-winning, mobile-first edge AI application designed to predict and visualize space weather anomalies, specifically Total Electron Content (TEC) and ionospheric disturbances. Developed in collaboration with ISRO and the Physics Department, this application processes 7 years of historical GPS receiver data and live hardware sensor feeds to provide infrastructure-level predictive intelligence directly on a mobile device.

## Core Architecture

### 1. The Edge Intelligence (TFLite)
* Powered by a custom Multi-Layer Neural Network trained entirely on a massive, 7-year ISRO GPS receiver dataset.
* The model was converted and quantized into **TensorFlow Lite (`tflite_flutter`)** to allow for high-speed, offline-capable, low-latency TEC predictions directly on the mobile edge, bypassing the need for heavy cloud inference.

### 2. Real-Time Hardware Integration
* Integrates live magnetic field strength data captured via a **Proton Precession Magnetometer** stationed at the local Thevara observatory.
* Data is pushed to a **Firebase Realtime Database** and instantly synced to the Flutter client, ensuring scientists have minute-by-minute updates.

### 3. Global API Telemetry
* Interfaces with **NASA OMNIWeb** utilizing asynchronous REST APIs (`dio`) to fetch surrounding interplanetary parameters (IMF, IMF-Bz, By, Bx, SymH).

## The User Interface (Analytical Panels)

The application is built around two primary analytical dashboards powered by `fl_chart` for high-performance rendering:

* **Panel 1: Magnetic Field Parameter Comparison**
  * Visualizes the hourly averaged geomagnetic field data from the local Thevara station alongside NASA OMNIWeb data (IMF Magnitude Avg, Bz GSE).
  * Allows users to dynamically select dates and parameter types to generate custom, real-time comparison reports.

* **Panel 2: TEC Prediction & Disturbance Mapping**
  * Displays both 1-minute and hourly average predictions for Adjusted TEC values using the onboard TFLite model.
  * Maps the Equatorial Electrojet ($\Delta$H) change in the local geomagnetic field.
  * Plots the Sym-H values, providing a complete, synchronized view of ionospheric disturbances.

## Technical Stack & Dependencies
* **Framework:** Flutter (`sdk: flutter`)
* **State Management & UI:** `provider`, `fl_chart`, `shimmer`, `flutter_spinkit`, `lottie`
* **Edge ML:** `tflite_flutter`
* **Backend & Auth:** `firebase_core`, `firebase_database`, `cloud_firestore`, `firebase_auth`
* **Networking & Local Storage:** `http`, `dio`, `shared_preferences`, `flutter_config`

## Installation & Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Harigovind04/Equatorial-Space-Weather-Application-for-Ionospheric-Research.git
