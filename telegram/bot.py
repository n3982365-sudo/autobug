import asyncio, json
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes
from api.redis_client import r
from api.settings import settings

_APP = None

async def start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    chat = update.effective_chat.id
    await update.message.reply_text(f"AutoBug linked. chat_id={chat}\nAdd it to TELEGRAM_ALLOWED_CHATS in .env and restart.")

async def _send(chat_id, text):
    if _APP:
        try: await _APP.bot.send_message(chat_id=chat_id, text=text)
        except Exception: pass

async def watch():
    pubsub = r.pubsub()
    pubsub.psubscribe("scan:*")
    while True:
        msg = pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
        if msg and msg.get("type") == "pmessage":
            try:
                evt = json.loads(msg["data"])
            except Exception:
                await asyncio.sleep(0.1); continue
            if evt.get("level") not in ("done", "warn"): 
                await asyncio.sleep(0.05); continue
            node = evt.get("node", "")
            if not any(k in node for k in ("vuln", "nuclei", "dalfox", "notify", "report")):
                await asyncio.sleep(0.05); continue
            text = f"{node}\nscan: {evt.get('scan_id')}\n{evt.get('payload')}"
            for chat in settings.chats:
                await _send(chat, text)
        await asyncio.sleep(0.05)

async def main():
    global _APP
    if not settings.TELEGRAM_BOT_TOKEN:
        print("no TELEGRAM_BOT_TOKEN, idling")
        while True: await asyncio.sleep(60)
    _APP = Application.builder().token(settings.TELEGRAM_BOT_TOKEN).build()
    _APP.add_handler(CommandHandler("start", start))
    await _APP.initialize()
    await _APP.start()
    await _APP.updater.start_polling()
    await watch()

if __name__ == "__main__":
    asyncio.run(main())
