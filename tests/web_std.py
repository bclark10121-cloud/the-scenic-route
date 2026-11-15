#!/usr/bin/env python3
# Standards check in the browser: the HUD stays inside a pretend notch (safe area), the touch pads show on touch
# and hide when a key is pressed, and the save file is written whole.
# usage: web_std.py [web build folder] [shots folder]
import asyncio, sys, subprocess, time, os
from playwright.async_api import async_playwright
OUT = sys.argv[1] if len(sys.argv) > 1 else "/home/claude/scenic-out/web"
SHOTS = sys.argv[2] if len(sys.argv) > 2 else "/home/claude/scenic-out/shots"
os.makedirs(SHOTS, exist_ok=True)
errs = []

async def main():
    srv = subprocess.Popen([sys.executable, "-m", "http.server", "8793", "--bind", "127.0.0.1"], cwd=OUT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); time.sleep(1)
    try:
        async with async_playwright() as p:
            b = await p.chromium.launch(executable_path="/usr/bin/google-chrome", args=["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--autoplay-policy=no-user-gesture-required"])
            ctx = await b.new_context(viewport={"width": 1280, "height": 720}, has_touch=True)
            pg = await ctx.new_page()
            pg.on("pageerror", lambda e: errs.append("page: " + str(e)))
            pg.on("console", lambda m: errs.append("console: " + m.text) if m.type == "error" else None)
            await pg.goto("http://127.0.0.1:8793/index.html?safe")
            await pg.wait_for_timeout(30000)
            await pg.screenshot(path=SHOTS + "/s1_title_safe.png")
            await pg.keyboard.press("Enter"); await pg.wait_for_timeout(1500)
            await pg.keyboard.press("Escape"); await pg.wait_for_timeout(500)
            cdp = await ctx.new_cdp_session(pg)
            await cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": 1060, "y": 590, "id": 1}]})
            await pg.wait_for_timeout(4000)
            await pg.screenshot(path=SHOTS + "/s2_touch_safe.png")
            await cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
            await pg.keyboard.press("j"); await pg.wait_for_timeout(1500)
            await pg.screenshot(path=SHOTS + "/s3_journal_safe.png"); await pg.keyboard.press("j")
            await pg.keyboard.down("ArrowUp"); await pg.wait_for_timeout(3000)
            await pg.screenshot(path=SHOTS + "/s4_keys_no_pads.png"); await pg.keyboard.up("ArrowUp")
            await pg.keyboard.press("h"); await pg.wait_for_timeout(14000)   # a setting change saves the game: Handling should read Loose after the reload
            await pg.reload(); await pg.wait_for_timeout(30000)
            await pg.keyboard.press("Enter"); await pg.wait_for_timeout(1500)
            await pg.keyboard.press("Escape"); await pg.wait_for_timeout(800)
            await pg.screenshot(path=SHOTS + "/s5_after_reload.png")
            await b.close()
    finally:
        srv.kill()
    print("errors", errs)

asyncio.run(main())
