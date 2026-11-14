# ShockProof (iOS, SwiftUI) - client for shockwaveAPI

## Run it
1. Backend (from the shockwaveAPI folder):
   `pip install -r requirements.txt`
   `uvicorn app.main:app --host 0.0.0.0 --port 8000`
2. Open `ShockProof.xcodeproj`, pick an iPhone simulator, Run. iOS 16+.
3. Real iPhone: on the first screen open "Backend" and enter your Mac's address, e.g. `http://192.168.1.20:8000`.

Using your own Xcode project instead? Delete any old ShockProof files first (Models.swift, Engine.swift, Views.swift),
add the 8 .swift files, and in Info set App Transport Security > Allow Arbitrary Loads = YES (plain http to your Mac).

## Screens and the endpoints behind them
- Link bank: GET /health, POST /api/link/create, POST /api/link/exchange, POST /api/accounts/{id}/sync
- Foundation (Layer 1): GET /api/accounts/{id}/profile (baseline, recurring series, 60-day day-by-day forecast), GET .../transactions
- Futures (Layer 2): POST /api/simulate (life events, forced shocks, 37-risk catalog, user profile gating)
- Rescue plan + cash cushion: more POST /api/simulate calls, each fix is re-simulated by the backend
- Stress: POST /api/stress-test
- Risks: GET /api/risks (switch risks off -> exclude_risk_keys)

## Assumptions (everything else comes from bank data or the backend)
Gig pay $110/shift, 4.5% savings APY, life-event template defaults (baby, car, home). All editable in the app or in AppModel.swift.
