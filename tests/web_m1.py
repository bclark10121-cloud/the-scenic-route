#!/usr/bin/env python3
# Milestone 1 browser check: the page loads with no errors, the title shows, the car drives with the keyboard,
# the three cameras and the handling button work, touch controls appear and drive the car.
# usage: web_m1.py [web build folder] [shots folder]
import asyncio, sys, subprocess, time, os
from playwright.async_api import async_playwright
OUT = sys.argv[1] if len(sys.argv) > 1 else "/home/claude/scenic-out/web"
SHOTS = sys.argv[2] if len(sys.argv) > 2 else "/home/claude/scenic-out/shots"
os.makedirs(SHOTS, exist_ok=True)
errs = []

async def main():
    srv = subprocess.Popen([sys.executable, "-m", "http.server", "8791", "--bind", "127.0.0.1"], cwd=OUT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); time.sleep(1)
    try:
        async with async_playwright() as p:
            b = await p.chromium.launch(executable_path="/usr/bin/google-chrome", args=["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
            ctx = await b.new_context(viewport={"width": 1280, "height": 720}, has_touch=True)
            pg = await ctx.new_page()
            pg.on("pageerror", lambda e: errs.append("page: " + str(e)))
            pg.on("console", lambda m: errs.append("console: " + m.text) if m.type == "error" else None)
            t0 = time.time()
            await pg.goto("http://127.0.0.1:8791/index.html" + (sys.argv[3] if len(sys.argv) > 3 else ""))
            await pg.wait_for_timeout(25000)
            await pg.screenshot(path=SHOTS + "/1_title.png")
            await pg.keyboard.press("Enter"); await pg.wait_for_timeout(1500)
            await pg.screenshot(path=SHOTS + "/2_start.png")
            await pg.keyboard.down("ArrowUp"); await pg.wait_for_timeout(6000)
            await pg.screenshot(path=SHOTS + "/3_driving.png")
            await pg.keyboard.down("ArrowRight"); await pg.wait_for_timeout(1500); await pg.keyboard.up("ArrowRight")
            await pg.wait_for_timeout(2500)
            await pg.screenshot(path=SHOTS + "/4_offroad.png")
            await pg.keyboard.up("ArrowUp")
            await pg.keyboard.press("c"); await pg.wait_for_timeout(2500)
            await pg.screenshot(path=SHOTS + "/5_cam2.png")
            await pg.keyboard.press("c"); await pg.wait_for_timeout(2500)
            await pg.screenshot(path=SHOTS + "/6_cam3.png")
            await pg.keyboard.press("c"); await pg.keyboard.press("h"); await pg.keyboard.press("r"); await pg.wait_for_timeout(2500)
            await pg.screenshot(path=SHOTS + "/7_reset.png")
            # touch: gas with one finger
            cdp = await ctx.new_cdp_session(pg)
            await cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": 1160, "y": 595, "id": 1}]})
            await pg.wait_for_timeout(4000)
            await cdp.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [{"x": 1160, "y": 595, "id": 1}, {"x": 300, "y": 500, "id": 2}]})
            await cdp.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [{"x": 1160, "y": 595, "id": 1}, {"x": 240, "y": 500, "id": 2}]})
            await pg.wait_for_timeout(1500)
            await pg.screenshot(path=SHOTS + "/8_touch.png")
            await cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
            await b.close()
    finally:
        srv.kill()
    print("errors", errs)

asyncio.run(main())
