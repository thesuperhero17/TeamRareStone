# 그리드용 섬네일과 얼굴 위치 만들기 (publish.ps1 이 실행함)
#
# - thumbs/<카테고리>/<파일>.jpg     짧은 변 440px (보통 화면용)
# - thumbs/<카테고리>/<파일>_2x.jpg  짧은 변 880px (촘촘한 화면·폰용)
# - data/focus.json  {"01_Nikke/0110_Diesel.jpg": [얼굴 가로 위치, 세로 위치, 원본 해시 8자리], ...}
#   위치는 0~1 비율. 사이트가 object-position 으로 써서 어떤 칸 모양이든 얼굴이 칸 안에 들어오게 함.
#
# 원본 내용(MD5)이 같으면 섬네일과 얼굴 찾기를 다시 하지 않음. 번호가 바뀌어도(파일 이름이 바뀌어도)
# 같은 그림이면 캐시를 그대로 씀. 원본이 없어진 섬네일은 지움.
#
# 실행: D:\Cluade\tools\face-venv\Scripts\python.exe -I scripts\make-thumbs.py

import hashlib
import json
import os
import re
import sys
from pathlib import Path

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
THUMBS = ROOT / "thumbs"
FOCUS_FILE = ROOT / "data" / "focus.json"
CACHE_FILE = ROOT / "data" / "focus-cache.json"   # 해시 -> [x, y, 얼굴 수]
OVERRIDE_FILE = ROOT / "data" / "focus-override.json"  # 손으로 고친 위치: {"해시 8자리" 또는 "카테고리/파일": [x, y]}

SHORT_1X = 440
SHORT_2X = 880
FALLBACK = [0.5, 0.3]  # 얼굴을 못 찾으면 위쪽 3분의 1
MIN_SCORE = 0.4


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, ValueError):
        return default


def save_thumb(img, short_side, out, quality):
    w, h = img.size
    scale = short_side / min(w, h)
    if scale >= 1:  # 원본이 더 작으면 키우지 않음
        small = img
    else:
        small = img.resize((round(w * scale), round(h * scale)), Image.LANCZOS, reducing_gap=3.0)
    out.parent.mkdir(parents=True, exist_ok=True)
    small.save(out, "JPEG", quality=quality, optimize=True, progressive=True)


_detector = None


def find_focus(img):
    """얼굴들을 감싸는 네모의 가운데를 0~1 비율로. 못 찾으면 None."""
    global _detector
    if _detector is None:
        from imgutils.detect import detect_faces
        _detector = detect_faces
    w, h = img.size
    faces = [f for f in _detector(img) if f[2] >= MIN_SCORE]
    if not faces:
        return None, 0
    x0 = min(f[0][0] for f in faces); y0 = min(f[0][1] for f in faces)
    x1 = max(f[0][2] for f in faces); y1 = max(f[0][3] for f in faces)
    fx = min(max((x0 + x1) / 2 / w, 0.0), 1.0)
    fy = min(max((y0 + y1) / 2 / h, 0.0), 1.0)
    return [round(fx, 3), round(fy, 3)], len(faces)


def main():
    cache = load_json(CACHE_FILE, {})
    override = load_json(OVERRIDE_FILE, {})
    focus = {}
    wanted = set()
    made = detected = missed = 0

    cats = sorted(p for p in ROOT.iterdir() if p.is_dir() and re.match(r"^\d{2}_", p.name))
    for cat in cats:
        for src in sorted(cat.glob("*.jpg")):
            rel = f"{cat.name}/{src.name}"
            digest = md5(src)
            short = digest[:8]
            t1 = THUMBS / cat.name / src.name
            t2 = THUMBS / cat.name / (src.stem + "_2x.jpg")
            wanted.update({t1, t2})

            entry = cache.get(digest)
            need_thumbs = not (t1.exists() and t2.exists()) or entry is None or entry[3:4] != [short]
            img = None
            if need_thumbs or entry is None:
                img = Image.open(src).convert("RGB")
            if need_thumbs:
                save_thumb(img, SHORT_1X, t1, 85)
                save_thumb(img, SHORT_2X, t2, 80)
                made += 1
            if entry is None:
                try:
                    pos, n = find_focus(img)
                except Exception as e:  # 인터넷이 끊겨 모델을 못 받는 경우 등
                    print(f"  얼굴 찾기 실패 ({rel}): {e}")
                    pos, n = None, -1
                if pos is None:
                    missed += 1
                    pos = FALLBACK
                if n >= 0:  # 실패한 건 캐시에 안 남겨서 다음에 다시 시도
                    cache[digest] = [pos[0], pos[1], n, short]
                detected += 1
                entry = [pos[0], pos[1], n, short]
            else:
                entry = entry[:3] + [short]
                cache[digest] = entry

            fx, fy = entry[0], entry[1]
            ov = override.get(short) or override.get(rel)
            if ov:
                fx, fy = ov[0], ov[1]
            focus[rel] = [fx, fy, short]

    # 원본이 없어진 섬네일 지우기
    removed = 0
    if THUMBS.exists():
        for p in THUMBS.rglob("*.jpg"):
            if p not in wanted:
                p.unlink()
                removed += 1
        for d in sorted((p for p in THUMBS.rglob("*") if p.is_dir()), reverse=True):
            if not any(d.iterdir()):
                d.rmdir()

    # 쓰이지 않는 캐시 정리 (지금 있는 그림 해시만 남김)
    live = {v[2] for v in focus.values()}
    cache = {k: v for k, v in cache.items() if k[:8] in live}

    FOCUS_FILE.write_text(json.dumps(focus, ensure_ascii=False, indent=0, sort_keys=True), encoding="utf-8")
    CACHE_FILE.write_text(json.dumps(cache, ensure_ascii=False, indent=0, sort_keys=True), encoding="utf-8")
    print(f"  섬네일 새로 만든 그림 {made}장, 얼굴 새로 찾은 그림 {detected}장(못 찾음 {missed}장), 지운 섬네일 {removed}개, 전체 {len(focus)}장")


if __name__ == "__main__":
    sys.exit(main())
