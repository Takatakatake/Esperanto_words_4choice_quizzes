import random
from dataclasses import dataclass

# Constants from app.py
BASE_POINTS = 10
STAGE_MULTIPLIER = {
    "beginner": 1.0,
    "intermediate": 1.5,
    "advanced": 2.0,
}
STREAK_BONUS = 2.0
ACCURACY_BONUS_PER_Q = 2.0
HOF_THRESHOLD = 3000

@dataclass
class SimulationResult:
    stage: str
    num_questions: int
    accuracy: float
    total_points: float
    raw_points: float
    bonus_points: float

def simulate_session(stage: str, num_questions: int, accuracy: float) -> SimulationResult:
    multiplier = STAGE_MULTIPLIER[stage]
    
    # Simulate correct/incorrect pattern
    # We'll distribute errors evenly for "average" case, or random for realistic
    # For this sim, let's just do a simple probabilistic model
    
    rng = random.Random(42) # Fixed seed for reproducibility
    
    correct_count = 0
    streak = 0
    raw_points = 0.0
    
    # Generate a list of True/False based on accuracy
    results = [True] * int(num_questions * accuracy) + [False] * (num_questions - int(num_questions * accuracy))
    rng.shuffle(results)
    
    for is_correct in results:
        if is_correct:
            correct_count += 1
            streak += 1
            streak_bonus = max(0, streak - 1) * STREAK_BONUS
            raw_points += BASE_POINTS * multiplier + streak_bonus
        else:
            streak = 0
            # No points for incorrect
            
    final_accuracy = correct_count / num_questions if num_questions > 0 else 0
    accuracy_bonus = final_accuracy * num_questions * ACCURACY_BONUS_PER_Q
    total_points = raw_points + accuracy_bonus
    
    return SimulationResult(stage, num_questions, final_accuracy, total_points, raw_points, accuracy_bonus)

def main():
    print(f"--- Scoring Simulation (HOF Threshold: {HOF_THRESHOLD}) ---")
    print(f"Base: {BASE_POINTS}, Streak Bonus: {STREAK_BONUS}, Acc Bonus/Q: {ACCURACY_BONUS_PER_Q}")
    
    scenarios = [
        ("beginner", 20, 1.0), # Perfect beginner
        ("beginner", 20, 0.8), # Good beginner
        ("beginner", 20, 0.5), # Struggling beginner
        ("intermediate", 25, 1.0),
        ("intermediate", 25, 0.8),
        ("advanced", 30, 1.0),
        ("advanced", 30, 0.8),
    ]
    
    for stage, n_q, acc in scenarios:
        res = simulate_session(stage, n_q, acc)
        sessions_to_hof = HOF_THRESHOLD / res.total_points
        print(f"\nStage: {stage.upper()}, Qs: {n_q}, Acc: {acc*100:.0f}%")
        print(f"  Total: {res.total_points:.1f} (Raw: {res.raw_points:.1f} + Bonus: {res.bonus_points:.1f})")
        print(f"  Sessions to HOF: {sessions_to_hof:.1f}")

if __name__ == "__main__":
    main()
