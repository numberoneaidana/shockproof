

🔗 **Live Demo:** [https://shoockproof.vercel.app](https://shoockproof.vercel.app) 

**Target Audience:** US Adults, ages 25–45 (B2C, Web-only).
60% of Americans cannot cover a $1,000 emergency. Existing financial tools (like Mint or YNAB) are backward-looking—they only show you what you *already spent*. They do not answer the fundamental, anxiety-inducing question: **"If I lose my job next month, will I survive?"**

**ShockProof** is a web-based financial resilience tool. We build a "financial twin" from your bank data and replay it through **3,000 Monte Carlo simulations**. 

Instead of just showing you a scary chart, ShockProof provides a **Rescue Plan**—a step-by-step, mathematically proven list of actions you can take today to drop your risk of bankruptcy to near zero.

### Key Features:
*   **The Fan Chart:** Visualizes 3,000 possible futures, showing the median outcome and the worst-case (1 in 20) scenarios.
*   **The Rescue Plan Engine:** Automatically tests interventions (e.g., canceling subscriptions, picking up gig work) sequentially through the simulator to find the cheapest, most effective fixes.
*   **Stress-Test Lab:** Instantly run specific disasters (Layoffs, Medical Bills, Car Crashes) against your current cash flow.
*   **Gamified Loading:** The `CashCatcher` mini-game keeps users engaged while the backend crunches 3,000 paths of complex financial math.

---

We designed ShockProof as a B2C Freemium SaaS:
*   **Free Tier:** Link bank account, view your baseline financial twin, and run one basic simulation.
*   **ShockProof Pro ($7.99/mo or $59/yr):** Unlocks unlimited custom simulations (baby, house, car), the personalized Rescue Plan, and continuous cash-cushion monitoring.
*   **Affiliate Revenue (Bonus):** When the Rescue Plan suggests moving cash to a High-Yield Savings Account (HYSA), we route the user to partners (e.g., Wealthfront, Marcus) and collect a ~$50 CPA referral fee. We monetize the exact action that saves the user's financial life.

---

We deliberately chose **"Math over AI"**. You do not want an LLM hallucinating when it comes to paying rent. ShockProof uses deterministic mathematical simulation.

*   **Frontend:** React, Context API, Neo-Brutalist Custom CSS (Fully responsive, web-only).
*   **Backend:** Python (FastAPI), custom Monte Carlo simulation engine (3,000 paths), loan amortization math (`pmt`).
*   **Data Modeling:** Standard deviations of variable spending, recurring transaction detection, probability distributions for life shocks.

---

To ensure a flawless, instant demo experience without waiting for 30-second Render cold starts or wrestling with unpredictable PDF bank statement parsing, we have made the following adjustments:

1.  **Pre-loaded Demo Data:** The live app is pre-loaded with a realistic sample bank profile (income, rent, subscriptions). You can immediately navigate to the **Futures** tab and click **"Simulate my future"**.
2.  **Mocked Integrations:** Bank parsing (Plaid) and Payments (Stripe) are mocked for the 24-hour demo. The core Monte Carlo engine and the Rescue Plan logic are 100% live and functional.
3.  **The Game:** Click "Simulate" and you will see a game (tap the coins, block the shocks). This is a deliberate UX feature to gamify the loading time while the Python backend computes.

---

## 💻 Running Locally

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/shockproof.git
   cd shockproof
