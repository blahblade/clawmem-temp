#!/usr/bin/env bash
# ===================================================================
# ClawMemory-X · Stress Test Demo (真的能跑出 token 节省)
# 场景:模拟一个真实的 50 轮 OpenClaw 编码对话
# 对照:No Memory(累积历史) vs ClawMemory-X(salience 压缩 + 召回)
# ===================================================================

set -e

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m'

cd "$(dirname "$0")/.."
source .venv/bin/activate

clear
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  ClawMemory-X · 50 轮真实对话压力测试                          ║${NC}"
echo -e "${BOLD}║  No Memory 累积历史 vs ClawMemory-X 智能压缩                 ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
sleep 1

echo -e "${BOLD}▶ 场景设定${NC}"
echo ""
echo "  模拟一个 50 轮的真实 OpenClaw 编程对话:"
echo "  - 10 轮 用户提需求 / 做决策(高价值 - 必须保留)"
echo "  - 15 轮 代码讨论 / bug fix(中价值 - 可压缩)"
echo "  - 25 轮 确认 / 闲聊 / 'ok' 'thanks'(低价值 - 可丢弃)"
echo ""
echo "  两种模式都跑第 51 轮提问:「我们这个项目用什么技术栈?」"
echo "  对比两种模式下 context 累积的 token 数"
echo ""
sleep 3

python - <<'PY'
"""Realistic 50-turn stress test comparing No Memory vs ClawMemory-X."""
import asyncio, json, random
from benchmark.metrics import count_tokens
from salience.scorer import score_messages
from policy.current import get_current_params

# ── Step 1: 构造真实感很强的 50 轮对话 ──────────────────────
random.seed(42)  # 保证可复现

# 10 条高价值决策(每条 80-150 tokens 的真实决策陈述)
high_value = [
    "决定:这个爬虫项目后端用 FastAPI,数据库用 PostgreSQL RDS (us-east-1),缓存用 Redis 6.2。不要用 Django,因为我们团队 90% 是 FastAPI 背景。",
    "架构拍板:embedding 模型选 bge-m3-zh,vector store 用 Chroma 0.5,reranker 用 BAAI/bge-reranker-v2-m3。不上 Pinecone(成本考虑)。",
    "部署规则:生产环境必须蓝绿部署,rollback 窗口 10 分钟。health check endpoint 是 /api/v1/health,返回 200 才算健康。",
    "客户 ACME 特殊规则:周报格式固定 [ACME Weekly] yyyy-mm-dd,中文撰写,周五 18:00 前 SMTP 发送到 ops@acme.com。",
    "退款 SOP 确认:金额 <500 元客服直接办,500-5000 主管审批,>5000 财务总监 + 法务会签。记录在 Jira 里。",
    "事故响应等级:P0 必须 5 分钟内 PagerDuty + 企业微信 at CTO,P1 30 分钟,P2 入次日日报。不允许 P0 走 Slack。",
    "研究项目技术栈定了:数据集 GSM8K + MATH (500 题 sample),模型 Qwen2.5-7B-Instruct + LoRA,指标 exact match + GPT-4o-judged。",
    "爬虫 scope:Python + FastAPI + Playwright,目标只有 Amazon 和 Taobao,只取 price history,不要评论/图片/description。",
    "RAG 架构 final call:Chroma (persistent mode) + bge-m3 embedding,k=10 召回,rerank top-3。不用 Pinecone 也不用 Weaviate。",
    "合规要求记录:PII 必须 SHA-256 hash 存储,日志保留 90 天自动删除,敏感词(枪支/违禁品)触发 escalate_to_human。",
]

# 15 条中价值讨论(每条 100-200 tokens 的技术讨论)
mid_value = [
    "关于 async handler 的问题:我查了一下,FastAPI 的 Depends 在 async endpoint 里会共享 pool,所以我们 SQLAlchemy 的 AsyncEngine 可以直接传。但注意 scoped_session 不是 async-safe 的。",
    "error 报出来了:`sqlalchemy.exc.InvalidRequestError: This session is in 'prepared' state`。我查 stackoverflow 说是 commit 前又 flush 了一次,我在 repo.py line 47 加了个 try/except 捕获。",
    "CORS 配置我试了 allow_origins=['*'] 不行,改成 ['http://localhost:5173', 'http://localhost:3000'] 可以了,Chrome 和 Firefox 都测过。Safari 还没测。",
    "测试 coverage 目前 67%,主要缺 services/ 下面的 order_service 和 payment_service。我准备今天下午补这两个,用 pytest-asyncio + httpx.AsyncClient。",
    "Dockerfile 里 multi-stage build 优化了一下,从 1.2GB 降到 380MB。主要是 builder stage 装 dev deps,runtime stage 只复制 .venv + source。",
    "CI/CD 挂了一次:GitHub Actions runner 没有 poetry,我加了 - uses: snok/install-poetry@v1 before install step。现在应该稳定了。",
    "查了 Chroma 的 docs:persistent_directory 需要是绝对路径,相对路径在 Docker 里会迷路。我已经改成 /data/chroma 了。",
    "embedding batch size 设 32 最快,再大会 CUDA OOM。bge-m3 context length 是 8192,不需要额外 chunking。",
    "我加了个 rate limiter,用 slowapi,100 req/min per IP。配合 Cloudflare 的 DDoS protection 应该够了。",
    "WebSocket 的 connection 数监控加上了,Prometheus 指标是 ws_active_connections,Grafana 看板也配好了。",
    "Redis 我选 6.2 不是 7.0,因为 7.0 的 ACL 配置改了不少东西,我们 ops 同学还没来得及学。先稳妥 6.2。",
    "Python 3.11 在 benchmark 里比 3.10 快 15%,我本地验过一些 heavy compute 的代码。升级到 3.11 没有 breaking change。",
    "关于 JWT:我们用 RS256 不用 HS256,因为 public key 可以分发给多个 service,不用共享 secret。expire 设 15 分钟。",
    "我试了 httpx 3 的 async client,比 aiohttp 快一点,API 也更清爽。打算下个 sprint 全部迁过来。",
    "Sentry 接上了,环境变量是 SENTRY_DSN,只在 prod 开,dev/staging 不开避免噪声。",
]

# 25 条低价值(每条 5-30 tokens,确认/寒暄/调试拉锯)
low_value = [
    "好的", "收到", "嗯", "ok", "OK", "好", "明白", "ok 明白", "好的我去试试", "嗯嗯",
    "让我想想", "稍等", "我看看", "我再试试", "让我确认一下",
    "可以", "没问题", "对", "是的", "应该可以",
    "差不多是这样", "基本同意", "thanks!", "谢谢",  "不客气",
]

# 按顺序把 50 轮拼起来
all_turns = []
for h in high_value: all_turns.append({"role": "user", "content": h})
for m in mid_value:  all_turns.append({"role": "user", "content": m})
for l in low_value:  all_turns.append({"role": "assistant", "content": l})
assert len(all_turns) == 50

print("  ▶ 已生成 50 轮模拟对话")
print(f"    - 高价值决策 : {len(high_value)} 条")
print(f"    - 中价值讨论 : {len(mid_value)} 条")
print(f"    - 低价值寒暄 : {len(low_value)} 条")
print()

async def main():
    # ── 方案 A: No Memory ─────────────────────────────────────
    # 模拟:第 51 轮提问时,需要把前 50 轮完整历史塞进 prompt
    # 这是没有记忆系统的 Agent 的必然做法
    no_mem_tokens = count_tokens(all_turns)

    # 再加第 51 轮的问题本身
    final_question = "我们这个项目用什么技术栈?完整列出来。"
    no_mem_tokens += count_tokens(final_question)

    print("  ▶ 方案 A · No Memory")
    print(f"    (第 51 轮提问,前 50 轮历史完整塞进 prompt)")
    print(f"    Context 大小 : {no_mem_tokens:>7,} tokens")
    print()

    # ── 方案 B: ClawMemory-X ──────────────────────────────────
    # 过程:
    # 1. 每条 message 打 salience 分
    # 2. < cutoff 的被压缩成 episodic summary
    # 3. ≥ cutoff 的进入 vector store
    # 4. 第 51 轮提问时,只召回 top_k 条相关 + summary
    params = get_current_params()
    cutoff = float(params["salience_cutoff"])
    top_k = int(params["top_k"])

    print("  ▶ 方案 B · ClawMemory-X")
    print(f"    (第 51 轮提问,只召回 top_{top_k} 条相关记忆)")

    scores = await score_messages(all_turns)
    kept = [t for t, s in zip(all_turns, scores) if s >= cutoff]
    dropped = [t for t, s in zip(all_turns, scores) if s < cutoff]

    # 模拟召回:用户问"技术栈",relevant terms 匹配
    query = "技术栈 tech stack FastAPI Python Chroma"
    query_terms = set(query.lower().split() + ["技术栈", "项目", "框架"])

    scored_kept = []
    for t in kept:
        content_lower = t["content"].lower()
        hit = sum(1 for term in query_terms if term in content_lower)
        scored_kept.append((t, hit))
    scored_kept.sort(key=lambda x: -x[1])
    retrieved = [t for t, h in scored_kept[:top_k]]

    # Episodic summary: 把 dropped 合并成一条
    summary_turn = {
        "role": "system",
        "content": f"[Episodic summary of {len(dropped)} low-salience turns: iteration "
                   f"acknowledgments, debug dialogue exchanges, confirmations. Key events preserved above.]"
    }

    clawmem_context = retrieved + [summary_turn, {"role": "user", "content": final_question}]
    clawmem_tokens = count_tokens(clawmem_context)

    print(f"    - 召回 retrieved  : {len(retrieved)} 条高相关")
    print(f"    - 压缩 summary    : {len(dropped)} 条 → 1 条")
    print(f"    Context 大小    : {clawmem_tokens:>7,} tokens")
    print()

    # ── 对比 ──────────────────────────────────────────────────
    saved = no_mem_tokens - clawmem_tokens
    pct = saved / no_mem_tokens * 100

    print("  ▶ 对比结果")
    print(f"    ┌──────────────────────┬──────────────┐")
    print(f"    │ No Memory            │ {no_mem_tokens:>7,} tokens │")
    print(f"    │ ClawMemory-X         │ {clawmem_tokens:>7,} tokens │")
    print(f"    └──────────────────────┴──────────────┘")
    print()
    print(f"    💰 Token 节省           : {saved:,} tokens")
    print(f"    📉 节省比例             : {pct:.1f} %")
    print()

    # ── 商业化规模折算 ──
    USD_PER_M = 2.50
    daily_sessions = 10_000  # 中等规模应用
    daily_saved = saved * daily_sessions
    daily_usd = daily_saved / 1_000_000 * USD_PER_M
    annual_usd = daily_usd * 365

    print(f"    💵 按 GPT-4o API $2.50 / 1M input tokens 折算:")
    print(f"       假设:日均 10,000 个 50-turn 对话 session")
    print(f"       每天节省 : ${daily_usd:>8,.0f}")
    print(f"       每年节省 : ${annual_usd:>8,.0f}")

    # 存结果
    with open("/tmp/stress_result.json", "w") as f:
        json.dump({
            "no_mem_tokens": no_mem_tokens,
            "clawmem_tokens": clawmem_tokens,
            "saved_tokens": saved,
            "saved_pct": pct,
            "annual_usd": annual_usd,
        }, f, indent=2)

asyncio.run(main())
PY

echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✅  演示完成 · 现场 30 秒可重跑                              ${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo ""
