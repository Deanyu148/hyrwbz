#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
定期删除 CNB 仓库多余的 release/tag，只保留 GitHub 最新 N 个版本。

每周一凌晨 3 点由流水线触发。以 GitHub published_at 时间戳为基准，
保留最新 N 个 release，CNB 上其余 release 和对应 git tag 全部删除。
删除操作复用 mirror_release.py 内的 cnb_delete_release / cnb_delete_tag。

环境变量：
    CNB_TOKEN   必填，CNB 访问令牌（流水线自动注入）
    GITHUB_REPO GitHub 源仓库
    CNB_REPO    CNB 目标仓库
"""

import argparse
import os
import sys

KEEP_N = 5  # 保留最新 N 个版本


def _release_ts(r):
    return r.get("published_at") or r.get("created_at") or ""


def latest_n_tags(gh_releases, n=KEEP_N):
    """按 published_at 倒序取最新 n 个非草稿 release 的 tag（新→旧）。"""
    candidates = [r for r in gh_releases if r.get("tag_name") and not r.get("draft")]
    candidates.sort(key=_release_ts, reverse=True)
    return [r.get("tag_name") for r in candidates[:n]]


def main():
    parser = argparse.ArgumentParser(
        description="删除 CNB 多余 release/tag，只保留 GitHub 最新 %d 个版本" % KEEP_N)
    parser.add_argument("--github-repo", default=os.environ.get("GITHUB_REPO", ""),
                        help="GitHub 源仓库")
    parser.add_argument("--cnb-repo", default=os.environ.get("CNB_REPO", ""),
                        help="CNB 目标仓库（格式 org/repo）")
    parser.add_argument("--github-token", default=os.environ.get("GITHUB_TOKEN", ""),
                        help="GitHub Token（可选）")
    parser.add_argument("--keep", type=int, default=KEEP_N,
                        help="保留最新版本数，默认 %d" % KEEP_N)
    parser.add_argument("--dry-run", action="store_true", help="只列出将删除的版本，不实际删除")
    args = parser.parse_args()

    token = os.environ.get("CNB_TOKEN", "")
    if not token and not args.dry_run:
        print("[错误] 缺少环境变量 CNB_TOKEN，无法调用 CNB API。"
              "云原生构建流水线会自动注入，本地调试请手动设置。", file=sys.stderr)
        return 2

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import mirror_release as m

    print("== 1/3 获取 GitHub releases: %s" % args.github_repo)
    gh_releases = m.gh_list_releases(args.github_repo, args.github_token)
    keep_tags = set(latest_n_tags(gh_releases, args.keep))
    print("   保留最新 %d 个版本: %s" % (len(keep_tags), sorted(keep_tags, key=m.parse_version)))

    print("== 2/3 获取 CNB 现有 releases: %s" % args.cnb_repo)
    cnb_releases = m.cnb_list_releases(args.cnb_repo, token)
    cnb_tag_to_id = {r.get("tag_name"): r.get("id")
                     for r in cnb_releases if r.get("tag_name")}
    print("   CNB 共 %d 个 release" % len(cnb_releases))

    # 待删除 = CNB 有、且不在保留集合内
    to_delete = sorted(set(cnb_tag_to_id.keys()) - keep_tags,
                       key=lambda t: (t, m.parse_version(t)))
    print("== 3/3 将删除 %d 个多余版本" % len(to_delete))
    if not to_delete:
        print("   无多余版本，无需删除。")
        return 0
    for tag in to_delete:
        print("   - %s" % tag)

    if args.dry_run:
        print("[dry-run] 仅列出，不执行删除。")
        return 0

    deleted = failed = 0
    for tag in to_delete:
        rel_id = cnb_tag_to_id.get(tag)
        try:
            # 先删 release（若有），再删 tag —— 与 cleanup_extra_tags 顺序一致
            if rel_id is not None:
                m.cnb_delete_release(args.cnb_repo, token, str(rel_id))
                print("   🗑 删除 release %s" % tag)
            m.cnb_delete_tag(args.cnb_repo, token, tag)
            deleted += 1
            print("   🗑 删除 tag %s" % tag)
        except Exception as e:  # noqa: BLE001
            failed += 1
            print("   ❌ 删除 %s 失败: %s" % (tag, e), file=sys.stderr)

    print("\n===== 删除汇总 =====")
    print("成功删除: %d 个版本" % deleted)
    print("失败: %d 个版本" % failed)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
