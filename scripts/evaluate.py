"""Aggregate manually labelled, held-out trials; never fabricate missing ground truth."""
import argparse
import csv
import json
from pathlib import Path
from statistics import mean

def rows(path):
    if not path.exists():
        return []
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))

def edit_distance(a, b):
    previous = list(range(len(b) + 1))
    for i, char in enumerate(a, 1):
        current = [i]
        for j, other in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (char != other)))
        previous = current
    return previous[-1]

def ratio(a, b):
    return a / b if b else None

def summarize(folder):
    objects = rows(folder / "object_trials.csv")
    tp, fp, fn = (sum(int(row[key]) for row in objects) for key in ("tp", "fp", "fn"))
    distances = rows(folder / "distance_trials.csv")
    valid = [row for row in distances if row["estimate_m"].strip()]
    errors = [abs(float(row["estimate_m"]) - float(row["truth_m"])) for row in valid]
    faces = rows(folder / "face_trials.csv")
    known = [row for row in faces if row["expected_id"] != "unknown"]
    strangers = [row for row in faces if row["expected_id"] == "unknown"]
    text = rows(folder / "ocr_trials.csv")
    voice = rows(folder / "voice_trials.csv")
    return {
        "objects": {"rows": len(objects), "precision": ratio(tp, tp + fp), "recall": ratio(tp, tp + fn)},
        "distance": {"trials": len(distances), "coverage": ratio(len(valid), len(distances)), "mae_m": mean(errors) if errors else None},
        "faces": {"known_trials": len(known), "unknown_trials": len(strangers),
                  "known_accuracy": ratio(sum(row["expected_id"] == row["predicted_id"] for row in known), len(known)),
                  "false_accept_rate": ratio(sum(row["predicted_id"] != "unknown" for row in strangers), len(strangers))},
        "ocr": {"trials": len(text), "character_error_rate": ratio(sum(edit_distance(row["reference"], row["hypothesis"]) for row in text), sum(len(row["reference"]) for row in text))},
        "voice": {"trials": len(voice), "command_accuracy": ratio(sum(row["expected_command"] == row["predicted_command"] for row in voice), len(voice))},
    }

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path, nargs="?", default=Path("evaluation"))
    args = parser.parse_args()
    print(json.dumps(summarize(args.folder), indent=2, allow_nan=False))
