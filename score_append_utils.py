from __future__ import annotations

from typing import Dict, Optional

import gspread
import streamlit as st


_CREDENTIAL_KEYS = {
    "type",
    "project_id",
    "private_key_id",
    "private_key",
    "client_email",
    "client_id",
    "auth_uri",
    "token_uri",
    "auth_provider_x509_cert_url",
    "client_x509_cert_url",
    "universe_domain",
}

_WS_CACHE: Dict[str, gspread.Worksheet] = {}
_HEADER_CACHE: Dict[str, list[str]] = {}
_RECENT_SAVE_IDS: Dict[str, set[str]] = {}
_RECENT_SAVE_IDS_LIMIT = 2048


def _to_plain_dict(value) -> Dict:
    if value is None:
        return {}
    if isinstance(value, dict):
        return value
    try:
        return dict(value)
    except Exception:
        return {}


def _get_conn_config() -> Dict:
    try:
        secrets = st.secrets
    except Exception:
        return {}
    conn = _to_plain_dict(_to_plain_dict(secrets).get("connections", {}).get("gsheets"))
    return conn


def _build_cache_key(conn: Dict, worksheet_name: str) -> Optional[str]:
    target = str(conn.get("spreadsheet") or conn.get("spreadsheet_url") or "").strip()
    if not target:
        return None
    return f"{target}::{worksheet_name}"


def _open_worksheet(worksheet_name: str) -> tuple[Optional[gspread.Worksheet], Optional[str]]:
    conn = _get_conn_config()
    if not conn:
        return None, None
    cache_key = _build_cache_key(conn, worksheet_name)
    if cache_key is None:
        return None, None

    target = cache_key.split("::", 1)[0]
    cached = _WS_CACHE.get(cache_key)
    if cached is not None:
        return cached, cache_key

    creds = {k: conn.get(k) for k in _CREDENTIAL_KEYS if conn.get(k)}
    if not creds:
        return None, cache_key

    try:
        client = gspread.service_account_from_dict(creds)
        if target.startswith("http://") or target.startswith("https://"):
            ss = client.open_by_url(target)
        else:
            ss = client.open_by_key(target)
        ws = ss.worksheet(worksheet_name)
        _WS_CACHE[cache_key] = ws
        return ws, cache_key
    except Exception:
        return None, cache_key


def _save_id_exists(ws: gspread.Worksheet, headers, save_id: str) -> bool:
    if not save_id or "save_id" not in headers:
        return False
    try:
        col_idx = headers.index("save_id") + 1
        values = ws.col_values(col_idx)
    except Exception:
        return False
    return any(str(v).strip() == save_id for v in values[1:])


def append_score_row_fast(record: Dict, worksheet_name: str) -> Optional[bool]:
    """
    Fast-path append for Scores sheet.

    Returns:
      - True: append succeeded or idempotent duplicate already exists
      - False: attempted but failed (caller may retry/fallback)
      - None: fast path unavailable; caller should fallback
    """
    ws, cache_key = _open_worksheet(worksheet_name)
    if ws is None:
        return None

    headers = _HEADER_CACHE.get(cache_key or "")
    if not headers:
        try:
            headers = [str(h).strip() for h in ws.row_values(1)]
            if cache_key:
                _HEADER_CACHE[cache_key] = headers
        except Exception:
            return None
    if not headers:
        return None

    # If schema changed, refresh headers once before deciding to fall back.
    if any(k not in headers for k in record.keys()):
        try:
            refreshed = [str(h).strip() for h in ws.row_values(1)]
        except Exception:
            refreshed = headers
        if refreshed:
            headers = refreshed
            if cache_key:
                _HEADER_CACHE[cache_key] = headers
        if any(k not in headers for k in record.keys()):
            # Preserve unknown keys by falling back to the legacy full-frame path.
            return None

    save_id = str(record.get("save_id", "")).strip()
    recent_ids = _RECENT_SAVE_IDS.setdefault(cache_key or "__default__", set())
    # Keep retries idempotent in-process without extra network reads.
    if save_id and save_id in recent_ids:
        return True

    row = ["" if record.get(h) is None else str(record.get(h)) for h in headers]
    try:
        ws.append_row(row, value_input_option="RAW")
        if save_id:
            recent_ids.add(save_id)
            # Process lifetime can be long on Streamlit Cloud; cap in-memory id cache.
            if len(recent_ids) > _RECENT_SAVE_IDS_LIMIT:
                recent_ids.clear()
                recent_ids.add(save_id)
        return True
    except Exception:
        if save_id and _save_id_exists(ws, headers, save_id):
            recent_ids.add(save_id)
            return True
        if cache_key:
            _WS_CACHE.pop(cache_key, None)
            _HEADER_CACHE.pop(cache_key, None)
            _RECENT_SAVE_IDS.pop(cache_key, None)
        return False
