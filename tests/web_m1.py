#!/usr/bin/env python3
# Browser check: the page loads with no errors, the title shows, the car drives with the keyboard,
# auto drive pulls away by itself, each biome draws, the journal opens and touch controls drive the car.
# usage: web_m1.py [web build folder] [shots folder] [?fast]
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
            b = await p.chromium.launch(executable_path="/usr/bin/google-chrome", args=["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--autoplay-policy=no-user-gesture-required"])
            ctx = await b.new_context(viewport={"width": 1280, "height": 720}, has_touch=True)
            pg = await ctx.new_page()
            pg.on("pageerror", lambda e: errs.append("page: " + str(e)))
            pg.on("console", lambda m: errs.append("console: " + m.text) if m.type == "error" else None)
            await pg.goto("http://127.0.0.1:8791/index.html" + (sys.argv[3] if len(sys.argv) > 3 else ""))
            await pg.wait_for_timeout(30000)
            await pg.screenshot(path=SHOTS + "/1_title.png")
            await pg.keyboard.press("Enter"); await pg.wait_for_timeout(1500)
            await pg.keyboard.down("ArrowUp"); await pg.wait_for_timeout(6000)
            await pg.screenshot(path=SHOTS + "/2_driving.png")
            await pg.keyboard.up("ArrowUp")
            await pg.keyboard.press("Escape")   # open the menu so the row of options shows in the biome shots
            for n, name in [("1", "pine"), ("2", "gold"), ("3", "snow"), ("4", "desert")]:
                await pg.keyboard.press(n); await pg.wait_for_timeout(3500)
                await pg.screenshot(path=SHOTS + "/3_%s.png" % name)
            await pg.keyboard.press("Minus"); await pg.wait_for_timeout(3500)
            await pg.screenshot(path=SHOTS + "/3_autumn.png")
            await pg.keyboard.press("x"); await pg.wait_for_timeout(5000)   # Christmas theme on
            await pg.screenshot(path=SHOTS + "/3_xmas.png"); await pg.keyboard.press("x")
            await pg.keyboard.press("5"); await pg.wait_for_timeout(1500)   # a circuit: drive through the gate so the lap clock starts
            await pg.keyboard.down("ArrowUp"); await pg.wait_for_timeout(7000); await pg.keyboard.up("ArrowUp")
            await pg.screenshot(path=SHOTS + "/3_track.png")
            await pg.keyboard.press("g"); await pg.wait_for_timeout(9000)   # auto drive: no keys held, the car should pull away
            await pg.screenshot(path=SHOTS + "/4_auto.png"); await pg.keyboard.press("g")
            await pg.keyboard.press("j"); await pg.wait_for_timeout(1500)
            await pg.screenshot(path=SHOTS + "/5_journal.png"); await pg.keyboard.press("j")
            await pg.keyboard.press("c"); await pg.wait_for_timeout(2500)
            await pg.screenshot(path=SHOTS + "/6_cam_close.png"); await pg.keyboard.press("c"); await pg.keyboard.press("c")
            cdp = await ctx.new_cdp_session(pg)
            await cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": 1160, "y": 595, "id": 1}]})
            await pg.wait_for_timeout(4000)
            await pg.screenshot(path=SHOTS + "/7_touch.png")
            await cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
            # narrow window, like a phone held upright or a side panel
            await pg.set_viewport_size({"width": 640, "height": 690}); await pg.wait_for_timeout(1500)
            await pg.screenshot(path=SHOTS + "/8_narrow.png")
            await b.close()
    finally:
        srv.kill()
    print("errors", errs)

asyncio.run(main())
