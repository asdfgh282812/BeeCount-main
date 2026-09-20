#!/usr/bin/env python3
"""
一鍵發布 BeeCount 到 SideStore 自訂軟體源：
從最新的 .xcarchive 打包出 .ipa，再讀取 IPA 內 Info.plist 自動產生/更新
apps.json（SideStore / AltStore 格式），並提取 App 圖示轉成標準 PNG。

所有輸出（.ipa、apps.json、圖示 PNG）都寫在「執行這個腳本時的當前工作目錄」下。

最簡單的用法（在 Xcode 完成 Archive 之後，於你要存放發布檔案的資料夾內執行）：
    python3 build_apps_json.py
不需要任何參數——會自動抓最新的 .xcarchive、打包成 <AppName>_V<version>.ipa，
並套用下面的 DEFAULT_* 常數。
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone

# ==== 每次發布前，依需要直接修改這幾個常數，不用每次都在命令列打參數 ====
DEFAULT_ARCHIVES_DIR = os.path.expanduser("~/Library/Developer/Xcode/Archives")
DEFAULT_BASE_URL = "https://pnsgzomf.synology.me/sidestore"
DEFAULT_DEVELOPER = "andy huang"
DEFAULT_LOCALIZED_DESCRIPTION = "蜜蜂記帳 - 隱私優先的個人記帳 App"
# 抄自 docs/changes/2026-09-20-whats-new-356.md 的「新功能！」公告內容摘要，
# 每次發版前記得換成這次真正要公告的內容。
DEFAULT_CHANGELOG = """\
1. AI 記帳新增商家欄位，回饋金自動套用
2. AI 對話更聰明：查帳能力加強，回覆排版更好讀
3. 信用卡帳單與交易明細顯示優化
4. 信用卡紅利回饋計算更精準（修正週期與退款反算問題）
5. 轉帳顯示改為「轉出→轉入」帳戶，修正跨幣別金額
6. 修正帳戶初始資金與日曆週檢視的小問題"""
# ============================================================

INFO_PLIST_RE = re.compile(r"^Payload/([^/]+\.app)/Info\.plist$")


# ---------------------------------------------------------------------------
# 步驟 1：從 .xcarchive 打包出 .ipa（等同手動 Payload/ 壓縮流程）
# ---------------------------------------------------------------------------

def find_latest_archive(archives_dir: str) -> str:
    archives: list[tuple[float, str]] = []
    for root, dirs, _files in os.walk(archives_dir):
        for d in list(dirs):
            if d.endswith(".xcarchive"):
                full = os.path.join(root, d)
                archives.append((os.path.getmtime(full), full))
                dirs.remove(d)  # 不需要往 .xcarchive 內部繼續走
    if not archives:
        raise SystemExit(f"在 {archives_dir} 找不到任何 .xcarchive，請先在 Xcode 完成 Archive。")
    archives.sort(reverse=True)
    return archives[0][1]


def find_app_bundle_in_archive(archive_path: str) -> str:
    apps_dir = os.path.join(archive_path, "Products", "Applications")
    if not os.path.isdir(apps_dir):
        raise SystemExit(f"封存檔內找不到 Products/Applications: {archive_path}")
    for name in sorted(os.listdir(apps_dir)):
        if name.endswith(".app"):
            return os.path.join(apps_dir, name)
    raise SystemExit(f"在 {apps_dir} 找不到 .app")


def package_ipa_from_archive(archives_dir: str, archive_override: str | None, cwd: str) -> str:
    archive_path = archive_override or find_latest_archive(archives_dir)
    print(f"使用封存檔: {archive_path}")

    app_path = find_app_bundle_in_archive(archive_path)
    app_name = os.path.splitext(os.path.basename(app_path))[0]

    with open(os.path.join(app_path, "Info.plist"), "rb") as f:
        version = plistlib.load(f).get("CFBundleShortVersionString")
    if not version:
        raise SystemExit(f"{app_path}/Info.plist 缺少 CFBundleShortVersionString")

    out_path = os.path.join(cwd, f"{app_name}_V{version}.ipa")

    with tempfile.TemporaryDirectory() as work_dir:
        payload_dir = os.path.join(work_dir, "Payload")
        os.makedirs(payload_dir)
        shutil.copytree(app_path, os.path.join(payload_dir, os.path.basename(app_path)))

        if os.path.exists(out_path):
            os.remove(out_path)
        result = subprocess.run(["zip", "-qry", out_path, "Payload"], cwd=work_dir)
        if result.returncode != 0:
            raise SystemExit(f"zip 壓縮失敗，exit code {result.returncode}")

    print(f"✅ 已產生 IPA: {out_path}")
    return out_path


# ---------------------------------------------------------------------------
# 步驟 2：讀取 .ipa 內的 Info.plist / 圖示
# ---------------------------------------------------------------------------

def find_info_plist(zf: zipfile.ZipFile) -> tuple[str, str]:
    for name in zf.namelist():
        m = INFO_PLIST_RE.match(name)
        if m:
            return name, m.group(1)
    raise SystemExit("在 IPA 內找不到 Payload/*.app/Info.plist，請確認打包結構正確")


def read_info_plist(zf: zipfile.ZipFile, plist_path: str) -> dict:
    with zf.open(plist_path) as f:
        data = f.read()
    return plistlib.loads(data)  # 自動判斷 binary / XML plist


def pick_icon_entry(zf: zipfile.ZipFile, app_dir: str, info: dict) -> str | None:
    """在 .app 目錄裡找出最合適的圖示 PNG（挑選符合命名前綴中檔案體積最大者，近似最高解析度）。"""
    prefix = f"Payload/{app_dir}/"
    png_entries = [
        n
        for n in zf.namelist()
        if n.startswith(prefix) and n.lower().endswith(".png") and "/" not in n[len(prefix):]
    ]
    if not png_entries:
        return None

    icon_bases: list[str] = []
    icons_dict = info.get("CFBundleIcons") or {}
    primary = icons_dict.get("CFBundlePrimaryIcon") or {}
    icon_bases.extend(primary.get("CFBundleIconFiles") or [])
    icon_name = icons_dict.get("CFBundleIconName")
    if icon_name:
        icon_bases.append(icon_name)
    # 舊式 key，部分工具鏈仍會寫入
    icon_bases.extend(info.get("CFBundleIconFiles") or [])

    candidates: list[str] = []
    for base in icon_bases:
        base_lower = base.lower()
        for n in png_entries:
            if os.path.basename(n).lower().startswith(base_lower):
                candidates.append(n)

    if not candidates:
        candidates = [n for n in png_entries if "icon" in os.path.basename(n).lower()]

    if not candidates:
        return None

    candidates.sort(key=lambda n: zf.getinfo(n).file_size, reverse=True)
    return candidates[0]


def extract_and_convert_icon(zf: zipfile.ZipFile, icon_entry: str, out_path: str) -> None:
    """iOS App 圖示是 Apple 專用的 CgBI 壓縮 PNG，一般 PNG 解碼器讀不了；用 macOS 內建的 sips 轉成標準 PNG。"""
    raw = zf.read(icon_entry)
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp.write(raw)
        tmp_path = tmp.name
    try:
        subprocess.run(
            ["sips", "-s", "format", "png", tmp_path, "--out", out_path],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        raise SystemExit(f"圖示轉換失敗（sips）: {e.stderr}") from e
    finally:
        os.unlink(tmp_path)


def iso8601_utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------------------
# 步驟 3：就地更新 / 新增 apps.json 條目
# ---------------------------------------------------------------------------

def build_app_entry(
    *,
    name: str,
    bundle_id: str,
    developer: str,
    version: str,
    version_date: str,
    version_description: str,
    download_url: str,
    localized_description: str,
    icon_url: str,
    size: int,
) -> dict:
    # 依規格範例保持固定的 key 順序，方便 diff / review
    return {
        "name": name,
        "bundleIdentifier": bundle_id,
        "developerName": developer,
        "version": version,
        "versionDate": version_date,
        "versionDescription": version_description,
        "downloadURL": download_url,
        "localizedDescription": localized_description,
        "iconURL": icon_url,
        "size": size,
    }


def load_or_init_apps_json(path: str, source_name: str, source_identifier: str) -> dict:
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"name": source_name, "identifier": source_identifier, "apps": []}


def upsert_app(data: dict, entry: dict) -> str:
    apps = data.setdefault("apps", [])
    for i, existing in enumerate(apps):
        if existing.get("bundleIdentifier") == entry["bundleIdentifier"]:
            apps[i] = {**existing, **entry}
            return "updated"
    apps.append(entry)
    return "added"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ipa", default=None, help="已打包好的 .ipa 檔案路徑；省略時自動從最新的 .xcarchive 打包一份")
    parser.add_argument("--archives-dir", default=DEFAULT_ARCHIVES_DIR, help="Xcode Archives 根目錄，找不到 --ipa 時才會用到")
    parser.add_argument("--archive", default=None, help="指定特定 .xcarchive 路徑；省略則自動抓最新的")
    parser.add_argument("--apps-json", default="apps.json", help="要更新／建立的 apps.json 路徑，預設為當前目錄下的 apps.json")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help=f"NAS 對外的 base URL，預設 {DEFAULT_BASE_URL}")
    parser.add_argument("--changelog", default=DEFAULT_CHANGELOG, help="本次更新說明（versionDescription），預設用程式碼裡的 DEFAULT_CHANGELOG")
    parser.add_argument("--developer", default=DEFAULT_DEVELOPER, help=f"開發者名稱，預設 {DEFAULT_DEVELOPER}")
    parser.add_argument("--localized-description", default=None, help="App 功能描述；省略時新增用 DEFAULT_LOCALIZED_DESCRIPTION，更新既有 App 則保留原值")
    parser.add_argument("--display-name", default=None, help="覆寫顯示名稱，預設讀取 Info.plist 的 CFBundleDisplayName/CFBundleName")
    parser.add_argument("--ipa-filename", default=None, help="downloadURL 使用的檔名，預設為實際使用的 .ipa 原始檔名")
    parser.add_argument("--icon-out-dir", default=None, help="轉出的圖示 PNG 存放目錄，預設為當前工作目錄")
    parser.add_argument("--icon-filename", default=None, help="圖示輸出檔名，預設為 <bundleIdentifier>.png（版本更新時檔名不變，iconURL 免改）")
    parser.add_argument("--source-name", default="My Custom Apps", help="僅在 apps.json 不存在、需新建時使用")
    parser.add_argument("--source-identifier", default="com.custom.source", help="僅在 apps.json 不存在、需新建時使用")
    args = parser.parse_args()

    cwd = os.getcwd()

    ipa_path = os.path.abspath(args.ipa) if args.ipa else package_ipa_from_archive(args.archives_dir, args.archive, cwd)
    if not os.path.isfile(ipa_path):
        raise SystemExit(f"找不到 IPA 檔案: {ipa_path}")

    apps_json_path = os.path.abspath(args.apps_json)
    icon_out_dir = os.path.abspath(args.icon_out_dir) if args.icon_out_dir else cwd
    os.makedirs(icon_out_dir, exist_ok=True)

    size_bytes = os.path.getsize(ipa_path)  # 精確位元組數，不四捨五入

    with zipfile.ZipFile(ipa_path) as zf:
        plist_path, app_dir = find_info_plist(zf)
        info = read_info_plist(zf, plist_path)

        bundle_id = info.get("CFBundleIdentifier")
        version = info.get("CFBundleShortVersionString")
        if not bundle_id or not version:
            raise SystemExit("Info.plist 缺少 CFBundleIdentifier 或 CFBundleShortVersionString")

        display_name = args.display_name or info.get("CFBundleDisplayName") or info.get("CFBundleName") or bundle_id

        icon_filename = args.icon_filename or f"{bundle_id}.png"
        icon_out_path = os.path.join(icon_out_dir, icon_filename)
        icon_entry = pick_icon_entry(zf, app_dir, info)
        if icon_entry:
            extract_and_convert_icon(zf, icon_entry, icon_out_path)
        else:
            print(f"⚠️  在 {app_dir} 內找不到符合的圖示檔，略過圖示提取，請自行提供 {icon_out_path}", file=sys.stderr)

    ipa_filename = args.ipa_filename or os.path.basename(ipa_path)
    download_url = f"{args.base_url.rstrip('/')}/{ipa_filename}"
    icon_url = f"{args.base_url.rstrip('/')}/{icon_filename}"
    version_date = iso8601_utc_now()

    data = load_or_init_apps_json(apps_json_path, args.source_name, args.source_identifier)

    # 更新既有 App 時，localizedDescription 若未傳入就保留舊值；新增時才套用 DEFAULT_LOCALIZED_DESCRIPTION
    existing = next((a for a in data.get("apps", []) if a.get("bundleIdentifier") == bundle_id), None)
    localized_description = (
        args.localized_description
        if args.localized_description is not None
        else (existing.get("localizedDescription", "") if existing else DEFAULT_LOCALIZED_DESCRIPTION)
    )

    entry = build_app_entry(
        name=display_name,
        bundle_id=bundle_id,
        developer=args.developer,
        version=version,
        version_date=version_date,
        version_description=args.changelog,
        download_url=download_url,
        localized_description=localized_description,
        icon_url=icon_url,
        size=size_bytes,
    )

    action = upsert_app(data, entry)

    with open(apps_json_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"✅ {action} bundleIdentifier={bundle_id} version={version} size={size_bytes} bytes")
    print(f"   versionDate = {version_date}")
    print(f"   downloadURL = {download_url}")
    print(f"   iconURL     = {icon_url}")
    print(f"   apps.json   -> {apps_json_path}")
    print(f"   icon PNG    -> {icon_out_path if icon_entry else '(未產出，需手動提供)'}")
    print()
    print("接下來把以下檔案上傳到 NAS 對應目錄（維持相同檔名）：")
    print(f"   - {apps_json_path}")
    print(f"   - {ipa_path}")
    if icon_entry:
        print(f"   - {icon_out_path}")


if __name__ == "__main__":
    main()
