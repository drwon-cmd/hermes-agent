#!/usr/bin/env python3
"""Estimate STT cost for a given audio file.

Outputs JSON: {duration_seconds, duration_human, estimated_cost_usd, estimated_cost_krw}

Usage:
    python estimate_cost.py --audio-path /path/to/audio.ogg
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys


WHISPER_COST_PER_MIN_USD = 0.006  # OpenAI Whisper-1 (2026-05 fetch)
USD_TO_KRW = 1350  # approximate, refresh quarterly


def get_audio_duration_seconds(audio_path: str) -> float:
    """Try multiple methods to extract audio duration."""
    if not os.path.exists(audio_path):
        raise FileNotFoundError(f"Audio not found: {audio_path}")

    # Method 1: ffprobe (most reliable, ffmpeg is in Hermes base image)
    try:
        result = subprocess.run(
            [
                "ffprobe",
                "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                audio_path,
            ],
            capture_output=True,
            text=True,
            timeout=30,
            check=True,
        )
        return float(result.stdout.strip())
    except (subprocess.SubprocessError, ValueError, FileNotFoundError) as e:
        pass  # try next method

    # Method 2: mutagen (Python lib, if installed)
    try:
        from mutagen import File as MutagenFile  # type: ignore
        audio = MutagenFile(audio_path)
        if audio and audio.info:
            return float(audio.info.length)
    except ImportError:
        pass
    except Exception:
        pass

    raise RuntimeError(
        f"Failed to extract duration from {audio_path}. "
        "Install ffmpeg (already in Hermes base) or mutagen."
    )


def format_duration(seconds: float) -> str:
    minutes = int(seconds // 60)
    secs = int(seconds % 60)
    if minutes >= 60:
        hours = minutes // 60
        rem_min = minutes % 60
        return f"{hours}시간 {rem_min}분 {secs}초"
    return f"{minutes}분 {secs}초"


def estimate_cost(duration_seconds: float) -> dict:
    duration_min = duration_seconds / 60
    cost_usd = round(duration_min * WHISPER_COST_PER_MIN_USD, 4)
    cost_krw = round(cost_usd * USD_TO_KRW)
    return {
        "duration_seconds": round(duration_seconds, 2),
        "duration_human": format_duration(duration_seconds),
        "estimated_cost_usd": cost_usd,
        "estimated_cost_krw": cost_krw,
        "whisper_rate_per_min_usd": WHISPER_COST_PER_MIN_USD,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Estimate STT cost for audio file")
    parser.add_argument("--audio-path", required=True, help="Path to audio file")
    args = parser.parse_args()

    try:
        duration = get_audio_duration_seconds(args.audio_path)
        result = estimate_cost(duration)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception as e:
        error_output = {
            "error": str(e),
            "audio_path": args.audio_path,
        }
        print(json.dumps(error_output, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
