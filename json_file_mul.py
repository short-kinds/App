import os, json, uuid, re
from typing import Dict, Any, List
from supabase import create_client
from dotenv import load_dotenv

load_dotenv()
URL = os.getenv("SUPABASE_URL")
SRK = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
assert URL and SRK, ".env에 SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY가 필요합니다."

sb = create_client(URL, SRK)

def normalize_playback_id(val: str) -> str:
    if not val:
        raise ValueError("mux.playback_id가 비었습니다.")
    if val.startswith("http"):
        m = re.search(r"stream\.mux\.com/([^/?]+)", val)
        if not m:
            raise ValueError("m3u8 URL 형식 오류")
        pid = m.group(1)
        pid = re.sub(r"\.m3u8.*$", "", pid)  # 확장자/쿼리 제거
        return pid
    return val

def _build_rows(rec: Dict[str, Any]) -> (Dict[str, Any], Dict[str, Any] | None):
    # 안정적(결정적) UUID: logical_id 기준
    _id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"shortkinds:{rec['logical_id']}"))

    mux = rec.get("mux", {}) or {}
    p_id = normalize_playback_id(mux.get("playback_id", ""))

    shorts_row = {
        "id": _id,
        "logical_id": rec["logical_id"],
        "title": rec["title"],
        "outlet_name": rec.get("outlet_name"),
        "reporter": rec.get("reporter"),
        "category": rec["category"],
        "trust_score": rec.get("trust_score"),
        "published_at": rec.get("published_at"),   # 'YYYY-MM-DD'
        "url": rec.get("url"),
        "mux_playback_id": p_id,
        "playback_policy": (mux.get("playback_policy") or "public").lower(),
        "duration_seconds": mux.get("duration_seconds"),
    }

    quiz = rec.get("quiz")
    quiz_row = None
    if quiz:
        quiz_row = {
            "item_id": _id,
            "question": quiz["question"],
            "options": quiz["options"],
            "answer_index": quiz["answer_index"],
            "cta_top": quiz.get("cta_top", False),
            "seconds_before_end": quiz.get("seconds_before_end", 5),
        }
    return shorts_row, quiz_row

def import_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # 최상단이 배열이거나, { "items": [...] } 형태도 지원
    if isinstance(data, list):
        records = data
    elif isinstance(data, dict) and isinstance(data.get("items"), list):
        records = data["items"]
    else:
        records = [data]  # 단일 객체도 처리

    shorts_rows: List[Dict[str, Any]] = []
    quiz_rows: List[Dict[str, Any]] = []
    ok, fail = 0, 0

    for i, rec in enumerate(records, 1):
        try:
            shorts_row, quiz_row = _build_rows(rec)
            shorts_rows.append(shorts_row)
            if quiz_row:
                quiz_rows.append(quiz_row)
            ok += 1
        except Exception as e:
            fail += 1
            print(f"[SKIP {i}] logical_id={rec.get('logical_id')} → {e}")

    if shorts_rows:
        sb.table("shorts").upsert(shorts_rows, on_conflict="id").execute()
    if quiz_rows:
        sb.table("quizzes").upsert(quiz_rows, on_conflict="item_id").execute()

    print(f"완료: 성공 {ok}건, 실패 {fail}건")

if __name__ == "__main__":
    import_json("./shorts.json")
