# -*- coding: utf-8 -*-
"""根据 template.csv 的表头生成 50 条测试记录，保存为二进制 xls（test.xls）。"""
import random

import xlwt

HEADERS = ["序号", "会议纪要号", "任务序号", "任务内容", "责任部门", "责任人",
           "计划完成时间", "延期时间", "实际完成时间", "备注"]

DEPTS = ["工程部", "技术部", "质量安全部", "物资部", "综合办公室", "计划经营部", "财务部"]
OWNERS = ["张伟", "李强", "王芳", "刘洋", "陈静", "赵磊", "孙敏", "周涛", "吴丽", "郑军"]
TASK_TEMPLATES = [
    "完成{}区域主体结构施工",
    "组织{}设备进场安装调试",
    "提交{}分项工程验收资料",
    "完成{}系统联调测试",
    "整改{}部位质量问题并复检",
    "编制{}专项施工方案并报审",
    "完成{}材料进场报验",
    "落实{}区域安全防护措施",
    "更新{}进度计划并上报",
    "协调{}专业交叉施工安排",
]
TOPICS = ["一号楼", "地下车库", "东侧基坑", "2#生产线", "配电室", "消防泵房",
          "屋面防水", "外幕墙", "厂区道路", "污水处理站", "综合管廊", "成品仓库"]
REMARKS = ["", "", "", "已提前完成", "受雨天影响", "待验收", "已完成并归档"]

random.seed(20260901)

wb = xlwt.Workbook(encoding="utf-8")
ws = wb.add_sheet("Sheet1")
for c, h in enumerate(HEADERS):
    ws.write(0, c, h)

rows = []
for i in range(1, 51):
    meeting_no = "HY-2026-%03d" % ((i - 1) // 5 + 1)
    task_no = (i - 1) % 5 + 1
    content = random.choice(TASK_TEMPLATES).format(random.choice(TOPICS))
    dept = random.choice(DEPTS)
    owner = random.choice(OWNERS)
    # 计划完成时间：2026 年内随机日期
    month = random.randint(1, 12)
    day = random.randint(1, 28)
    plan = "2026-%02d-%02d" % (month, day)
    # 约 1/4 有延期，延期到计划之后
    if random.random() < 0.25:
        delay = "2026-%02d-%02d" % (min(month + 1, 12), day)
    else:
        delay = ""
    # 约 2/3 已完成
    if random.random() < 2 / 3:
        actual = plan
    else:
        actual = ""
    remark = random.choice(REMARKS)
    rows.append([i, meeting_no, task_no, content, dept, owner, plan, delay, actual, remark])

for r, row in enumerate(rows, start=1):
    for c, v in enumerate(row):
        ws.write(r, c, v)

wb.save("test.xls")
print("已生成 test.xls，共 %d 条记录" % len(rows))
