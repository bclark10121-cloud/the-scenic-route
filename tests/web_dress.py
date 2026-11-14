#!/usr/bin/env python3
# Screenshots of the first bridge and the first road works. usage: web_dress.py [web build] [shots folder]
import asyncio, sys, subprocess, time, os
from playwright.async_api import async_playwright
OUT = sys.argv[1] if len(sys.argv) > 1 else "/home/claude/scenic-out/web"
SHOTS = sys.argv[2] if len(sys.argv) > 2 else "/home/claude/scenic-out/shots"
errs = []
async def main():
    srv = subprocess.Popen([sys.executable, "-m", "http.server", "8792", "--bind", "127.0.0.1"], cwd=OUT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); time.sleep(1)
    try:
        async with async_playwright() as p:
            b = await p.chromium.launch(executable_path="/usr/bin/google-chrome", args=["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
            pg = await b.new_page(viewport={"width": 1280, "height": 720})
            pg.on("pageerror", lambda e: errs.append("page: " + str(e)))
            pg.on("console", lambda m: errs.append("console: " + m.text) if m.type == "error" else None)
            await pg.goto("http://127.0.0.1:8792/index.html")
            await pg.wait_for_timeout(32000)
            await pg.keyboard.press("Enter"); await pg.wait_for_timeout(1000)
            await pg.keyboard.press("c"); await pg.wait_for_timeout(500)
            for key, name in [("9", "bridge"), ("0", "works")]:
                await pg.keyboard.press(key); await pg.wait_for_timeout(1000)
                await pg.keyboard.down("ArrowUp"); await pg.wait_for_timeout(5000); await pg.keyboard.up("ArrowUp")
                await pg.screenshot(path=SHOTS + "/9_%s.png" % name)
            await b.close()
    finally:
        srv.kill()
    print("errors", errs)
asyncio.run(main())
