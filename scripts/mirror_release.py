#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将 GitHub 仓库的 Releases（含预发布版）镜像同步到 CNB 仓库。

流程：
1. 通过 GitHub API 获取源仓库全部 release（分页；公开仓库无需认证，
   私有仓库需提供 GITHUB_TOKEN，且 token 需有该仓库读取权限）。
2. 通过 CNB API 获取目标仓库已有的 release tag 集合（分页）。
3. 对每个「GitHub 有而 CNB 没有」的非草稿 release：
   下载其全部附件 -> 在 CNB 创建同名 release -> 依次上传附件（三步式）。
4. GitHub 发布列表中最新的正式版设置 make_latest=true，其余为 false。

环境变量：
    CNB_TOKEN   必填，CNB 访问令牌（云原生构建流水线自动注入）
    CNB_API_BASE 可选，默认 https://api.cnb.cool
    GITHUB_TOKEN 可选，GitHub 访问令牌（镜像私有仓库 release 时必填）

依赖：仅 Python 3.8+ 标准库，无需第三方包。
"""

import argparse
import json
import os
import re
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

API_GITHUB = "https://api.github.com"
API_CNB = os.environ.get("CNB_API_BASE", "https://api.cnb.cool")
USER_AGENT = "as-cnb-mirror/1.0"
GITHUB_PAGE_SIZE = 100
CNB_PAGE_SIZE = 100


class ApiError(RuntimeError):
    def __init__(self, status, url, body):
        self.status = status
        self.url = url
        self.body = body
        super().__init__("HTTP %d %s: %s" % (status, url, (body or "")[:500]))


def _gh_headers(token):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": USER_AGENT}
    if token:
        headers["Authorization"] = "Bearer " + token
    return headers


def _cnb_headers(token):
    headers = {
        "Accept": "application/vnd.cnb.api+json",
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT,
    }
    if token:
        headers["Authorization"] = "Bearer " + token
    return headers


def _sleep_backoff(attempt):
    time.sleep(min(2 ** attempt, 30))


def http_json(url, headers=None, method="GET", payload=None, retries=4, timeout=120):
    """发送 JSON 请求并解析响应。payload 为 dict 时以 JSON 编码。"""
    hdrs = dict(headers or {})
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")

    last_err = None
    for attempt in range(retries):
        req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                body = resp.read()
            return json.loads(body.decode("utf-8")) if body else None
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "ignore")
            status = e.code
            if status == 429 or status >= 500:
                # 限流或服务端错误：等待后重试
                retry_after = e.headers.get("Retry-After")
                if retry_after and retry_after.isdigit():
                    time.sleep(min(int(retry_after), 60))
                else:
                    _sleep_backoff(attempt)
                last_err = ApiError(status, url, body)
                continue
            raise ApiError(status, url, body)
        except urllib.error.URLError as e:
            last_err = e
            _sleep_backoff(attempt)
    raise last_err


class _NoAuthRedirectHandler(urllib.request.HTTPRedirectHandler):
    """跟随 302 跳转时丢弃 Authorization 头。

    私有仓库附件经 GitHub API 会 302 到 S3 签名 URL，签名本身包含完整
    鉴权信息，若把原请求的 Authorization 头一并转发，可能导致签名校验
    失败；同时也不应把 token 泄露到 api.github.com 之外的主机。
    """

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new_req = super().redirect_request(req, fp, code, msg, headers, newurl)
        new_req.headers.pop("Authorization", None)
        return new_req


_OPENER = urllib.request.build_opener(_NoAuthRedirectHandler())


def download_file(url, dest, headers=None, retries=4, timeout=300):
    """下载文件到 dest，失败重试。跟随重定向但不转发 Authorization。"""
    hdrs = dict(headers or {})
    hdrs.setdefault("User-Agent", USER_AGENT)
    last_err = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=hdrs)
            with _OPENER.open(req, timeout=timeout) as resp, open(dest, "wb") as f:
                shutil.copyfileobj(resp, f)
            return True
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "ignore")
            status = e.code
            last_err = ApiError(status, url, body)
            if status != 429 and status < 500:
                break
            retry_after = e.headers.get("Retry-After")
            if retry_after and retry_after.isdigit():
                time.sleep(min(int(retry_after), 60))
            else:
                _sleep_backoff(attempt)
        except (urllib.error.URLError, OSError) as e:
            last_err = e
            _sleep_backoff(attempt)
    raise last_err


# ---------- GitHub ----------

def gh_list_releases(repo, token=""):
    """分页获取 GitHub 仓库全部 release。"""
    releases = []
    page = 1
    while True:
        url = "%s/repos/%s/releases?per_page=%d&page=%d" % (
            API_GITHUB, repo, GITHUB_PAGE_SIZE, page)
        data = http_json(url, headers=_gh_headers(token))
        if not data:
            break
        releases.extend(data)
        if len(data) < GITHUB_PAGE_SIZE:
            break
        page += 1
    return releases


# ---------- CNB ----------

def cnb_list_releases(repo, token):
    """分页获取 CNB 仓库全部 release。"""
    releases = []
    page = 1
    while True:
        url = "%s/%s/-/releases?page=%d&page_size=%d" % (
            API_CNB, repo, page, CNB_PAGE_SIZE)
        data = http_json(url, headers=_cnb_headers(token))
        if not data:
            break
        releases.extend(data)
        if len(data) < CNB_PAGE_SIZE:
            break
        page += 1
    return releases


def cnb_get_release_by_tag(repo, token, tag):
    """按 tag 查询 CNB release（用于幂等补全）。"""
    url = "%s/%s/-/releases/tags/%s" % (
        API_CNB, repo, urllib.parse.quote(tag, safe=""))
    return http_json(url, headers=_cnb_headers(token), retries=2)


def cnb_list_tags(repo, token):
    """分页获取 CNB 仓库全部 git tag 名称集合。"""
    names = set()
    page = 1
    while True:
        url = "%s/%s/-/git/tags?page=%d&page_size=%d" % (
            API_CNB, repo, page, CNB_PAGE_SIZE)
        data = http_json(url, headers=_cnb_headers(token))
        if not data:
            break
        for item in data:
            name = item.get("name")
            if name:
                names.add(name)
        if len(data) < CNB_PAGE_SIZE:
            break
        page += 1
    return names


def cnb_get_default_branch(repo, token):
    """获取 CNB 仓库默认分支名（用于创建 tag 时作为 target）。"""
    url = "%s/%s/-/git/head" % (API_CNB, repo)
    data = http_json(url, headers=_cnb_headers(token), retries=2)
    if not data or not data.get("name"):
        raise ApiError(0, url, "无法获取默认分支: %s" % json.dumps(data, ensure_ascii=False))
    return data["name"]


def cnb_create_tag(repo, token, tag, target, message=""):
    """在 CNB 仓库创建 git tag，指向 target（分支名/tag 名/commit sha）。"""
    url = "%s/%s/-/git/tags" % (API_CNB, repo)
    payload = {"name": tag, "target": target}
    if message:
        payload["message"] = message
    return http_json(url, headers=_cnb_headers(token), method="POST", payload=payload)
def cnb_delete_tag(repo, token, tag):
    """删除 CNB git tag（按名称）。tag 不存在（404）视为已清理。"""
    url = "%s/%s/-/git/tags/%s" % (API_CNB, repo, urllib.parse.quote(tag, safe=""))
    try:
        http_json(url, headers=_cnb_headers(token), method="DELETE", retries=2)
    except ApiError as e:
        if e.status == 404:
            return False
        raise
    return True


def cnb_delete_release(repo, token, release_id):
    """删除 CNB release（按 ID）。"""
    url = "%s/%s/-/releases/%s" % (API_CNB, repo, release_id)
    http_json(url, headers=_cnb_headers(token), method="DELETE", retries=2)
    return True




def cnb_create_release(repo, token, payload):
    """创建 CNB release，返回响应 dict。"""
    url = "%s/%s/-/releases" % (API_CNB, repo)
    return http_json(url, headers=_cnb_headers(token), method="POST", payload=payload)


def cnb_upload_asset(repo, token, release_id, file_path):
    """三步式上传附件：申请 URL -> PUT 文件 -> 确认。"""
    asset_name = os.path.basename(file_path)
    file_size = os.path.getsize(file_path)

    # 1. 申请预签名上传 URL
    url = "%s/%s/-/releases/%s/asset-upload-url" % (API_CNB, repo, release_id)
    info = http_json(
        url,
        headers=_cnb_headers(token),
        method="POST",
        payload={"asset_name": asset_name, "overwrite": True, "size": file_size},
    )
    if not info or "upload_url" not in info:
        raise ApiError(0, url, "asset-upload-url 未返回 upload_url: %s" % json.dumps(info, ensure_ascii=False))

    # 2. PUT 文件二进制
    upload_headers = {
        "Accept": "application/json",
        "Authorization": "Bearer " + token if token else "",
        "Content-Type": "application/octet-stream",
        "Content-Length": str(file_size),
        "User-Agent": USER_AGENT,
    }
    with open(file_path, "rb") as f:
        file_data = f.read()
    req = urllib.request.Request(info["upload_url"], data=file_data, headers=upload_headers, method="PUT")
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            status = resp.status
            resp.read()
    except urllib.error.HTTPError as e:
        raise ApiError(e.code, info["upload_url"], e.read().decode("utf-8", "ignore"))
    if status >= 300:
        raise ApiError(status, info["upload_url"], "PUT 上传附件失败")

    # 3. 确认上传（若返回 verify_url）
    verify_url = info.get("verify_url")
    if verify_url:
        http_json(verify_url, headers=_cnb_headers(token), method="POST", timeout=120)
    return True


# ---------- 主流程 ----------

def parse_version(tag):
    """将 tag 拆成版本号各段用于排序，如 v1.2.3 -> (1, 2, 3)；非版本 -> (-1,)。
    越大越新。无版本号的 tag 视作最小。
    """
    m = re.search(r"(\d+(?:\.\d+)*)", tag or "")
    if not m:
        return (-1,)
    return tuple(int(x) for x in m.group(1).split("."))


def pick_make_latest(gh_releases, tag):
    """GitHub 列表按创建时间倒序，第一个正式版（非预发布、非草稿）为最新正式版。
    若 tag 恰为该最新正式版则返回 "true"，其余（含预发布版）返回 "false"。
    """
    for r in gh_releases:
        if not r.get("prerelease") and not r.get("draft"):
            return "true" if r.get("tag_name") == tag else "false"
    return "false"
def cleanup_extra_tags(repo, token, github_tags):
    """删除 CNB 上 GitHub 不存在的 git tag，保持与 GitHub 一致。

    以 GitHub 的 tag 集合为基准，CNB 多出的全部删除。返回 (已删除数, 失败数)。
    """
    gh_set = {t for t in github_tags if t}
    try:
        cnb_tags = cnb_list_tags(repo, token)
    except Exception as e:  # noqa: BLE001
        print("清理多余 tag：拉取 CNB tag 列表失败: %s" % e, file=sys.stderr)
        return (0, 0)
    extra = sorted(cnb_tags - gh_set, key=parse_version)
    if not extra:
        print("清理多余 tag：CNB 共 %d 个 tag，与 GitHub 一致，无需删除" % len(cnb_tags))
        return (0, 0)
    print("清理多余 tag：将删除 %d 个（GitHub 无对应 release）" % len(extra))
    deleted = failed = 0
    for tag in extra:
        try:
            # 先删 release（若有），再删 tag
            try:
                rel = cnb_get_release_by_tag(repo, token, tag)
                if rel and rel.get("id") is not None:
                    cnb_delete_release(repo, token, str(rel["id"]))
                    print("   🗑 删除 release %s" % tag)
            except ApiError as e:
                # release 不存在（404）属正常，继续删 tag
                if e.status != 404:
                    raise
            cnb_delete_tag(repo, token, tag)
            deleted += 1
            print("   🗑 删除 tag %s" % tag)
        except Exception as e:  # noqa: BLE001
            failed += 1
            print("   ❌ 删除 tag %s 失败: %s" % (tag, e), file=sys.stderr)
    return (deleted, failed)




def _cnb_release_ts(r):
    """CNB release 时间戳，published_at 优先，回退 created_at。"""
    return r.get("published_at") or r.get("created_at") or ""


def delete_rebuild_tags(repo, token, rebuild_tags, cnb_releases, cnb_git_tags):
    """删除检查器判定为时间戳顺序不一致的 tag 集合，以便后续重新同步。

    检查器已对比 GitHub 与 CNB 双侧 release 的时间戳顺序，并算出错位区间
    （GitHub 顺序中最小错位位置到最大错位位置，含两端）的 tag 子集，通过
    --rebuild-tags 传入。同步器在此统一执行删除：先删 release 后删 tag，
    返回 (deleted, failed) 计数；被删除的 tag 由调用方加入待同步集合重建。

    顺序一致性判断不再由同步器自己做——CNB 不支持显式设置 release 时间戳，
    同步器按 GitHub published_at 由旧到新依次重建，重建后 CNB 的 created_at
    顺序天然与 GitHub published_at 顺序对齐。
    """
    if not rebuild_tags:
        return (0, 0)

    rb_set = set(rebuild_tags)
    cnb_by_tag = {r.get("tag_name"): r for r in cnb_releases
                  if r.get("tag_name") in rb_set}

    print("== 删除顺序不一致的版本（错位区间，含两端）后重建")
    print("   待删除重建: %s" % rebuild_tags)
    deleted = failed = 0
    for tag in rebuild_tags:
        try:
            # 先删 release（若有），再删 tag —— 顺序与 prune_releases 一致
            rel = cnb_by_tag.get(tag)
            if rel and rel.get("id") is not None:
                cnb_delete_release(repo, token, str(rel["id"]))
                print("   🗑 删除 release %s（顺序重建）" % tag)
            cnb_delete_tag(repo, token, tag)
            cnb_git_tags.discard(tag)
            deleted += 1
            print("   🗑 删除 tag %s（顺序重建）" % tag)
        except Exception as e:  # noqa: BLE001
            failed += 1
            print("   ❌ 顺序重建删除 %s 失败: %s" % (tag, e), file=sys.stderr)
    return (deleted, failed)


def pushplus_summary(github_repo, cnb_repo, ok_count, fail_count, sync_results,
                     latest_tag=None, cleanup_deleted=0, cleanup_failed=0):
    """同步结束后推送结果汇总到 PushPlus。失败不阻断主流程。

    环境变量：
        PUSHPLUS_TOKEN      PushPlus 个人 token（一对一推送）
        PUSHPLUS_SECRET_KEY 开放接口 secret_key（必填）
    任一缺失则跳过推送。
    """
    token = os.environ.get("PUSHPLUS_TOKEN", "")
    secret_key = os.environ.get("PUSHPLUS_SECRET_KEY", "")
    if not token or not secret_key:
        print("[PushPlus] 未设置 PUSHPLUS_TOKEN / PUSHPLUS_SECRET_KEY，跳过推送。")
        return

    try:
        from perk_pushplus import PushPlusClient  # noqa: WPS433
    except ImportError:
        print("[PushPlus] perk_pushplus 包未安装，跳过推送。")
        return

    title = "[Mirror] %s -> %s 同步完成" % (github_repo, cnb_repo)
    status = "全部成功" if fail_count == 0 else "有失败"
    cnb_repo_url = (os.environ.get("CNB_REPO_URL_HTTPS")
                    or "https://cnb.cool/%s" % cnb_repo).rstrip("/")
    releases_url = cnb_repo_url + "/-/releases/tag"
    if latest_tag:
        link_url = "%s/%s" % (
            releases_url, urllib.parse.quote(latest_tag, safe=""))
        link_text = "最新版本 %s" % latest_tag
        gh_link_url = "https://github.com/%s/releases/tag/%s" % (
            github_repo, urllib.parse.quote(latest_tag, safe=""))
        gh_link_text = "GitHub 源发布 %s" % latest_tag
    else:
        link_url = releases_url
        link_text = "全部发布版本"
        gh_link_url = "https://github.com/%s/releases" % github_repo
        gh_link_text = "GitHub 全部发布版本"
    rows = []
    for tag, state, msg in sync_results:
        icon = "✅" if state == "ok" else "❌"
        row = "<tr><td>%s</td><td>%s</td><td>%s</td></tr>" % (
            icon, tag, msg or "—")
        rows.append(row)
    cleanup_line = (
        "<p>清理多余 release/tag: <b>删除 %d</b> &nbsp; <b>失败 %d</b></p>"
        % (cleanup_deleted, cleanup_failed))
    body = (
        "<h3>同步汇总（%s）</h3>"
        "<p>源仓库: %s<br>目标仓库: %s</p>"
        '<p>下载地址：<a href="%s">%s</a></p>'
        '<p>备用地址：<a href="%s">%s</a></p>'
        "<p><b>成功: %d</b> &nbsp; <b>失败: %d</b></p>"
        "%s"
        "<table border=1 cellpadding=4 cellspacing=0>"
        "<tr><th>结果</th><th>Tag</th><th>说明</th></tr>"
        "%s</table>"
    ) % (status, github_repo, cnb_repo, link_url, link_text,
         gh_link_url, gh_link_text,
         ok_count, fail_count, cleanup_line, "".join(rows))

    try:
        client = (
            PushPlusClient.builder()
            .token(token)
            .secret_key(secret_key)
            .build()
        )
        short_code = client.send_simple(title, body)
        print("[PushPlus] 已推送，short_code=%s" % short_code)
    except Exception as e:  # noqa: BLE001
        print("[PushPlus] 推送失败: %s" % e)


def main():
    parser = argparse.ArgumentParser(description="将 GitHub Releases 镜像同步到 CNB")
    parser.add_argument("--github-repo", default=os.environ.get("GITHUB_REPO", ""),
                        help="GitHub 源仓库")
    parser.add_argument("--cnb-repo", default=os.environ.get("CNB_REPO", ""),
                        help="CNB 目标仓库（格式 org/repo）")
    parser.add_argument("--github-token", default=os.environ.get("GITHUB_TOKEN", ""),
                        help="GitHub Token（公开仓库可选；私有仓库必填，"
                             "token 需对该源仓库有读取权限）")
    parser.add_argument("--dry-run", action="store_true", help="仅对比版本，不下载不上传")
    parser.add_argument("--only-tags", default="",
                        help="只同步指定的 tag 集合（逗号分隔），由检查器规定；"
                             "该模式下跳过全量清理，删除交由 prune_releases.py")
    parser.add_argument("--rebuild-tags", default="",
                        help="检查器判定时间戳顺序不一致后，需删除重建的 tag 集合"
                             "（逗号分隔，仅 --only-tags 模式生效）；"
                             "同步器会先删这些 tag 对应的 release 再删 tag，然后重新同步")
    args = parser.parse_args()

    # 检查器规定的期望集合，保留传入顺序（GitHub published_at 新→旧），去重。
    # 用列表保序，顺序后续用于校验 CNB tag/release 顺序是否与 GitHub 一致。
    only_tags = None
    if args.only_tags:
        only_tags = []
        seen = set()
        for t in args.only_tags.split(","):
            t = t.strip()
            if t and t not in seen:
                only_tags.append(t)
                seen.add(t)

    # 检查器判定时间戳顺序不一致后指定的需删除重建的 tag 子集。
    # 仅 --only-tags 模式生效；子集必须是 only_tags 的真子集。
    rebuild_tags = []
    if args.rebuild_tags and only_tags is not None:
        seen_rb = set()
        only_set = set(only_tags)
        for t in args.rebuild_tags.split(","):
            t = t.strip()
            if t and t in only_set and t not in seen_rb:
                rebuild_tags.append(t)
                seen_rb.add(t)

    token = os.environ.get("CNB_TOKEN", "")
    if not token:
        print("[错误] 缺少环境变量 CNB_TOKEN，无法调用 CNB API。"
              "云原生构建流水线会自动注入，本地调试请手动设置。", file=sys.stderr)
        sys.exit(2)

    print("== 1/4 获取 GitHub releases: %s" % args.github_repo)
    try:
        gh_releases = gh_list_releases(args.github_repo, args.github_token)
    except ApiError as e:
        if e.status == 404:
            hint = ("仓库不存在或无权访问。若为私有仓库，请通过 --github-token "
                    "或环境变量 GITHUB_TOKEN 提供有该仓库读取权限的 token。")
        elif e.status == 401:
            hint = "GitHub Token 无效或已过期。"
        else:
            hint = ""
        print("[错误] 获取 GitHub releases 失败: %s%s" % (
            e, ("；" + hint) if hint else ""), file=sys.stderr)
        sys.exit(2)
    gh_tags = {r.get("tag_name") for r in gh_releases if r.get("tag_name")}
    print("   GitHub 共 %d 个 release" % len(gh_releases))

    print("== 2/4 获取 CNB 现有 releases: %s" % args.cnb_repo)
    cnb_releases = cnb_list_releases(args.cnb_repo, token)
    cnb_tags = {r.get("tag_name") for r in cnb_releases if r.get("tag_name")}
    print("   CNB 共 %d 个 release" % len(cnb_releases))

    print("== 2.5/4 获取 CNB 现有 git tags")
    cnb_git_tags = cnb_list_tags(args.cnb_repo, token)
    print("   CNB 共 %d 个 git tag" % len(cnb_git_tags))
    cnb_default_branch = cnb_get_default_branch(args.cnb_repo, token)
    print("   CNB 默认分支: %s" % cnb_default_branch)

    # 第一步：先删除 CNB 上 GitHub 不存在的 release 和 tag，保证与源一致。
    # --only-tags 模式下跳过全量清理，删除交由 prune_releases.py 周期执行。
    print("== 3/4 清理 CNB 多余的 release 和 tag")
    if args.dry_run or only_tags is not None:
        if only_tags is not None:
            print("   [--only-tags] 跳过全量清理，由 prune_releases.py 负责删除多余版本")
        else:
            print("   [dry-run] 跳过清理")
        cleanup_deleted, cleanup_failed = (0, 0)
    else:
        cleanup_deleted, cleanup_failed = cleanup_extra_tags(
            args.cnb_repo, token, gh_tags)
        # 清理后重新拉取 CNB 的 tag/release 集合，保证后续判断基于最新状态
        cnb_releases = cnb_list_releases(args.cnb_repo, token)
        cnb_tags = {r.get("tag_name") for r in cnb_releases if r.get("tag_name")}
        cnb_git_tags = cnb_list_tags(args.cnb_repo, token)
        print("   清理完成：删除 %d 个，失败 %d 个" % (cleanup_deleted, cleanup_failed))

    # 顺序一致性检查（仅 --only-tags 模式，即检查器驱动时生效）。
    # 检查器已对比 GitHub 与 CNB 双侧 release 时间戳顺序，把错位区间
    # （GitHub 顺序中最小错位位置到最大错位位置，含两端）通过 --rebuild-tags
    # 传入；同步器在此统一删除这些 release+tag（先删 release 后删 tag），
    # 然后加入待同步集合按时间戳由旧到新重新创建，使 CNB created_at 顺序
    # 与 GitHub published_at 顺序对齐。
    if only_tags is not None and not args.dry_run and rebuild_tags:
        print("== 2.6/4 删除检查器判定的顺序不一致版本")
        ord_deleted, ord_failed = delete_rebuild_tags(
            args.cnb_repo, token, rebuild_tags, cnb_releases, cnb_git_tags)
        if ord_deleted or ord_failed:
            # 删除后重新拉取 CNB 现状，被删除的 tag 会在下方加入待同步集合
            cnb_releases = cnb_list_releases(args.cnb_repo, token)
            cnb_tags = {r.get("tag_name") for r in cnb_releases
                        if r.get("tag_name")}
            cleanup_deleted += ord_deleted
            cleanup_failed += ord_failed
            print("   顺序重建：删除 %d 个，失败 %d 个，将重新同步" % (
                ord_deleted, ord_failed))

    # 待同步：GitHub 有、CNB 无、且非草稿。
    # --only-tags 模式下，只取检查器规定的 tag 子集（已按时间戳为最新5版），
    # 加上顺序重建删除后需重新创建的 tag。
    # 排序：按 GitHub published_at 时间戳由旧到新，保证最后留下最新版；
    # published_at 缺失回退 created_at，再回退 parse_version。
    def _release_ts(r):
        ts = r.get("published_at") or r.get("created_at") or ""
        return (ts, parse_version(r.get("tag_name") or ""))

    # 顺序重建删除的 tag 需要重新同步，加入待同步集合
    rebuild_set = set(rebuild_tags)

    pending = []
    for r in gh_releases:
        if r.get("draft"):
            continue
        tag = r.get("tag_name")
        if not tag:
            continue
        # 已存在于 CNB 且非顺序重建项 → 跳过
        if tag in cnb_tags and tag not in rebuild_set:
            continue
        if only_tags is not None and tag not in only_tags:
            continue
        pending.append(r)
    pending.sort(key=_release_ts)

    print("== 4/4 待同步 %d 个版本" % len(pending))
    if not pending:
        print("   全部已是最新，无需同步。")
        return 0
    for r in pending:
        pre = " [预发布]" if r.get("prerelease") else ""
        print("   - %s%s (%d 个附件)" % (
            r.get("tag_name"), pre, len(r.get("assets") or [])))

    if args.dry_run:
        print("[dry-run] 仅对比，不执行同步。")
        return 0

    print("== 开始同步")
    workdir = tempfile.mkdtemp(prefix="cnb_mirror_")
    ok_count = 0
    fail_count = 0
    sync_results = []  # [(tag, "ok"/"fail", message)]
    try:
        for i, r in enumerate(pending, 1):
            tag = r.get("tag_name")
            name = r.get("name") or tag
            body = r.get("body") or ""
            html_url = r.get("html_url") or ("https://github.com/%s/releases/tag/%s" % (args.github_repo, tag))
            make_latest = pick_make_latest(gh_releases, tag)
            print("\n[%d/%d] 同步 %s%s" % (i, len(pending), tag,
                  " [预发布]" if r.get("prerelease") else ""))
            try:
                # 3.0 若 CNB 缺少该 git tag，先创建（指向默认分支 HEAD）
                if tag not in cnb_git_tags:
                    print("   CNB 缺少 git tag %s，先创建（target=%s）" % (tag, cnb_default_branch))
                    try:
                        cnb_create_tag(args.cnb_repo, token, tag, cnb_default_branch,
                                        message="mirror from GitHub release %s" % tag)
                        cnb_git_tags.add(tag)
                        print("   ✅ tag 已创建")
                    except ApiError as e:
                        # 并发或重复创建时可能返回 409/422，忽略并复用
                        if e.status in (400, 409, 422):
                            cnb_git_tags.add(tag)
                            print("   tag 已存在（%s），跳过" % e.status)
                        else:
                            raise

                # 3.1 下载全部附件
                # 私有仓库的 browser_download_url 无法直接下载，需走
                # GitHub API 的 asset 端点并带 Accept: application/octet-stream，
                # 服务端会 302 到带签名的临时下载地址（公开仓库同样适用）。
                assets = r.get("assets") or []
                asset_files = []
                rel_dir = os.path.join(workdir, tag.replace("/", "_"))
                os.makedirs(rel_dir, exist_ok=True)
                for a in assets:
                    a_name = a.get("name")
                    if not a_name:
                        continue
                    if args.github_token and a.get("url"):
                        a_url = a["url"]
                        dl_headers = dict(_gh_headers(args.github_token),
                                          Accept="application/octet-stream")
                    else:
                        a_url = a.get("browser_download_url")
                        dl_headers = _gh_headers(args.github_token)
                    if not a_url:
                        print("   跳过无下载地址的附件: %s" % a_name)
                        continue
                    dest = os.path.join(rel_dir, a_name)
                    print("   下载 %s (%d bytes)" % (a_name, a.get("size", 0)))
                    download_file(a_url, dest, headers=dl_headers)
                    asset_files.append(dest)

                # 3.2 创建 CNB release
                mirror_body = (
                    "> 本版本由 CNB 云原生构建从 GitHub 自动镜像同步。\n"
                    "> 源发布: %s\n\n%s" % (html_url, body)
                ).strip()
                payload = {
                    "tag_name": tag,
                    "name": name,
                    "body": mirror_body,
                    "draft": False,
                    "prerelease": bool(r.get("prerelease")),
                    "make_latest": make_latest,
                }
                print("   创建 CNB release (make_latest=%s)" % make_latest)
                try:
                    created = cnb_create_release(args.cnb_repo, token, payload)
                    release_id = str(created.get("id"))
                    print("   release_id=%s" % release_id)
                except ApiError as e:
                    # 创建失败时尝试幂等补全：若该 tag 已存在 release 则复用之
                    if e.status in (400, 409, 422):
                        existing = cnb_get_release_by_tag(args.cnb_repo, token, tag)
                        if existing:
                            release_id = str(existing.get("id"))
                            print("   tag 已存在 release（%s），继续补全附件" % release_id)
                        else:
                            raise
                    else:
                        raise

                # 3.3 上传附件
                for j, f in enumerate(asset_files, 1):
                    print("   上传 [%d/%d] %s" % (j, len(asset_files), os.path.basename(f)))
                    cnb_upload_asset(args.cnb_repo, token, release_id, f)
                ok_count += 1
                sync_results.append((tag, "ok", ""))
                print("   ✅ 完成")
            except Exception as e:  # noqa: BLE001
                fail_count += 1
                sync_results.append((tag, "fail", str(e)))
                print("   ❌ 失败: %s" % e)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    print("\n===== 同步汇总 =====")
    print("成功: %d 个版本" % ok_count)
    print("失败: %d 个版本" % fail_count)
    print("清理: 删除 %d 个多余 tag/release，失败 %d 个" % (cleanup_deleted, cleanup_failed))

    # 只有本次实际同步成功（新增了 release）才推送通知；
    # 文件相同、无新增的情况下不推送，避免噪音。
    if ok_count:
        known_tags = cnb_tags | {t for t, s, _ in sync_results if s == "ok"}
        latest_tag = max(known_tags, key=parse_version) if known_tags else None
        pushplus_summary(args.github_repo, args.cnb_repo, ok_count, fail_count,
                         sync_results, latest_tag,
                         cleanup_deleted=cleanup_deleted, cleanup_failed=cleanup_failed)

    return 1 if fail_count else 0


def main_with_only_tags(github_repo, cnb_repo, github_token="", only_tags=None,
                              rebuild_tags=None):
    """供检查器直接调用的可编程入口，避免改写 sys.argv。

    github_repo / cnb_repo / github_token 同 main() 的同名参数；
    only_tags 为 tag 列表时只同步该子集，列表顺序即为检查器规定的期望顺序
    （GitHub published_at 新→旧），限定同步范围；
    rebuild_tags 为检查器判定时间戳顺序不一致后需删除重建的 tag 子集
    （错位区间，含两端），同步器先删这些 release+tag 再重新同步。
    返回 main() 的退出码。
    """
    argv = ["mirror_release.py",
            "--github-repo", github_repo,
            "--cnb-repo", cnb_repo]
    if github_token:
        argv += ["--github-token", github_token]
    if only_tags:
        argv += ["--only-tags", ",".join(only_tags)]
    if rebuild_tags:
        argv += ["--rebuild-tags", ",".join(rebuild_tags)]
    old_argv = sys.argv
    sys.argv = argv
    try:
        return main()
    finally:
        sys.argv = old_argv


if __name__ == "__main__":
    sys.exit(main())

