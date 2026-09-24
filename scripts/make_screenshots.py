#!/usr/bin/env python3
"""Capture the app with the current content/ and compose shareable images.

Runs the `Screenshots` scheme (ios/TripJournalUITests) on an iPhone simulator in light and dark mode, with the
app clock frozen on a trip day (`-TripNow`, DEBUG only) and a clean status bar, then writes to docs/assets/:
  hero-light.jpg, hero-dark.jpg   four framed screens under your app name and tagline (README top image)
  screens/<name>-<mode>.jpg       every captured screen, framed on its own
  social-preview.png              1280×640 image for GitHub's social preview and link cards
  demo.webp (with --video)        a short animated walk-through; demo.mp4 goes to the work directory
Run `python3 scripts/build_ios_resources.py` first. Requires Xcode 26, XcodeGen and Pillow; --video needs ffmpeg.
Captures run on a dedicated simulator ("OneTrip Screenshots (<model>)") that is erased first, so recordings can never
show other apps from your everyday simulator.
Usage: python3 scripts/make_screenshots.py [--device "iPhone 17 Pro"] [--now 2027-11-16T10:30] [--video]
"""
import argparse, json, os, shutil, signal, subprocess, sys, tempfile, time
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'ios/TripJournal.xcodeproj'
FONT = '/System/Library/Fonts/Hiragino Sans GB.ttc'  # W3 = index 0, W6 = index 2; ships with macOS
BRAND, SLOGAN = 'OneTrip · 一程', '每次旅行，都值得一个专属 App'
PITCH = ('告诉 AI Agent 你要去哪，', '得到一个原生、离线的 iPhone 旅行 App')
MARK = 'Made with OneTrip'
# Colours from ios/TripJournal/App/Design.swift (TripStyle.paper / green / coral).
THEME = {
    'light': {'bg': (247, 245, 237), 'bg2': (236, 232, 218), 'ink': (41, 79, 66), 'muted': (110, 118, 108), 'accent': (194, 92, 66)},
    'dark': {'bg': (20, 26, 23), 'bg2': (32, 42, 37), 'ink': (171, 209, 173), 'muted': (150, 160, 150), 'accent': (222, 132, 106), 'rim': (78, 90, 83)},
}
HERO = ['01-today', '02-itinerary', '04-place-detail', '08-phrases']
CAPTIONS = {'01-today': '今日', '02-itinerary': '行程', '03-places': '探索地点', '04-place-detail': '地点详情',
            '05-dining': '餐饮', '06-guides': '攻略', '07-travel-kit': '行囊', '08-phrases': '短句朗读'}


def run(*args, **kw):
    return subprocess.run(args, check=True, text=True, **kw)


def font(size, bold=False):
    return ImageFont.truetype(FONT, size, index=2 if bold else 0)


def device(model):
    """A dedicated simulator of the given model, erased before use: its home screen has nothing but stock apps."""
    name = f'OneTrip Screenshots ({model})'
    listing = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '-j', capture_output=True).stdout)
    udid = next((d['udid'] for runtime, devices in listing['devices'].items() if 'iOS' in runtime
                 for d in devices if d['name'] == name), None)
    if udid is None:
        udid = run('xcrun', 'simctl', 'create', name, model, capture_output=True).stdout.strip()
    subprocess.run(['xcrun', 'simctl', 'shutdown', udid], capture_output=True)  # fails harmlessly if not booted
    run('xcrun', 'simctl', 'erase', udid, capture_output=True)
    return udid


def bundle_id():
    settings = json.loads(run('xcodebuild', '-showBuildSettings', '-project', str(PROJECT), '-target', 'TripJournal', '-json',
                              capture_output=True).stdout)
    return settings[0]['buildSettings']['PRODUCT_BUNDLE_IDENTIFIER']


def test(udid, app, method, now, bundle, on_line=None):
    """Run one UI test; returns nothing, raises on failure. on_line(line) sees xcodebuild output live."""
    # Start from a fresh install: a saved plan from another trip (different trip id) is never overwritten, so the
    # app would refuse to open it; screenshots should also not show earlier ticks or favourites.
    subprocess.run(['xcrun', 'simctl', 'uninstall', udid, app], capture_output=True)
    env = dict(os.environ, TEST_RUNNER_TRIP_NOW=now)
    cmd = ['xcodebuild', 'test-without-building', '-project', str(PROJECT), '-scheme', 'Screenshots',
           '-destination', f'id={udid}', '-resultBundlePath', str(bundle),
           '-only-testing', f'TripJournalUITests/ScreenshotTests/{method}']
    with subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as proc:
        log = []
        for line in proc.stdout:
            log.append(line)
            if on_line: on_line(line)
    if proc.returncode:
        sys.stdout.write(''.join(log[-40:]))
        raise SystemExit(f'{method} failed')


def export(bundle, out):
    run('xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle), '--output-path', str(out), capture_output=True)
    shots = {}
    for test_case in json.loads((out / 'manifest.json').read_text()):
        for item in test_case.get('attachments', []):
            name = item.get('suggestedHumanReadableName', '')
            key = next((k for k in CAPTIONS if name.startswith(k)), None)
            if key: shots[key] = out / item['exportedFileName']
    return shots


def rounded(size, radius):
    mask = Image.new('L', size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return mask


def phone(path, height, rim=None):
    """Screenshot in a plain dark bezel with a soft shadow; drawn here, no device artwork needed."""
    screen = Image.open(path).convert('RGB')
    width = round(screen.width * height / screen.height)
    screen = screen.resize((width, height), Image.Resampling.LANCZOS)
    bezel = max(6, height // 70)
    radius = round(width * 0.14)
    body = Image.new('RGBA', (width + 2 * bezel, height + 2 * bezel), (0, 0, 0, 0))
    body.paste((22, 24, 23, 255), (0, 0), rounded(body.size, radius + bezel))
    if rim:  # keeps the dark bezel visible on a dark background
        ImageDraw.Draw(body).rounded_rectangle((0, 0, body.width - 1, body.height - 1), radius + bezel, outline=rim, width=3)
    body.paste(screen, (bezel, bezel), rounded(screen.size, radius))
    pad = height // 12
    shadow = Image.new('RGBA', (body.width + 2 * pad, body.height + 2 * pad), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 70), (pad, pad + pad // 3), rounded(body.size, radius + bezel))
    shadow = shadow.filter(ImageFilter.GaussianBlur(pad / 2.5))
    shadow.alpha_composite(body, (pad, pad))
    return shadow, pad


def background(size, theme):
    top, bottom = theme['bg'], theme['bg2']
    image = Image.new('RGB', size, top)
    draw = ImageDraw.Draw(image)
    for y in range(size[1]):
        t = y / max(1, size[1] - 1)
        draw.line((0, y, size[0], y), fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return image


def hero(shots, trip, mode, out):
    theme = THEME[mode]
    canvas = background((2400, 1560), theme)
    draw = ImageDraw.Draw(canvas)
    draw.text((140, 110), trip['appName'], font=font(88, True), fill=theme['ink'])
    draw.text((140, 225), trip.get('tagline', ''), font=font(40), fill=theme['muted'])
    draw.text((canvas.width - 140 - draw.textlength(MARK, font=font(28)), 150), MARK, font=font(28), fill=theme['muted'])
    keys = [k for k in HERO if k in shots]
    frames = [phone(shots[k], 1020, theme.get('rim')) for k in keys]
    gap = 56
    total = sum(f.width - 2 * pad for f, pad in frames) + gap * (len(frames) - 1)
    x, y = (canvas.width - total) // 2, 340
    for key, (frame, pad) in zip(keys, frames):
        canvas.paste(frame, (x - pad, y - pad), frame)
        label = CAPTIONS[key]
        w = draw.textlength(label, font=font(36, True))
        draw.text((x + (frame.width - 2 * pad - w) / 2, y + frame.height - 2 * pad + 36), label, font=font(36, True), fill=theme['ink'])
        x += frame.width - 2 * pad + gap
    canvas.save(out, quality=86, optimize=True, progressive=True)


def single(path, key, mode, out):
    theme = THEME[mode]
    frame, pad = phone(path, 1400, theme.get('rim'))
    canvas = background((frame.width - 2 * pad + 160, frame.height - 2 * pad + 260), theme)
    canvas.paste(frame, (80 - pad, 80 - pad), frame)
    draw = ImageDraw.Draw(canvas)
    label = CAPTIONS[key]
    draw.text(((canvas.width - draw.textlength(label, font=font(44, True))) / 2, canvas.height - 150), label, font=font(44, True), fill=theme['ink'])
    canvas.thumbnail((900, 2000), Image.Resampling.LANCZOS)
    canvas.save(out, quality=84, optimize=True, progressive=True)


def social(shots, out):
    theme = THEME['light']
    canvas = background((1280, 640), theme)
    draw = ImageDraw.Draw(canvas)
    draw.text((72, 150), BRAND, font=font(76, True), fill=theme['ink'])
    draw.text((72, 265), SLOGAN, font=font(38, True), fill=theme['accent'])
    y = 340
    for line in PITCH:
        draw.text((72, y), line, font=font(28), fill=theme['muted']); y += 44
    draw.text((72, 540), 'SwiftUI · 离线优先 · 小组件 · Agent 调研', font=font(24), fill=theme['muted'])
    x = 760
    for key in ('01-today', '04-place-detail'):
        if key not in shots: continue
        frame, pad = phone(shots[key], 560)
        canvas.paste(frame, (x - pad, 40 - pad + (0 if key == '01-today' else 30)), frame)
        x += frame.width - 2 * pad + 24
    canvas.save(out, optimize=True)


def video(udid, app, now, work, out):
    if not shutil.which('ffmpeg'): raise SystemExit('--video needs ffmpeg (brew install ffmpeg)')
    movie, marks = work / 'demo.mov', {}
    recorder = subprocess.Popen(['xcrun', 'simctl', 'io', udid, 'recordVideo', '--codec', 'h264', '--force', str(movie)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    start = time.monotonic(); time.sleep(1.5)

    def mark(line):
        if 'testDemoTour]' in line and ' started' in line: marks['begin'] = time.monotonic() - start
        if 'testDemoTour]' in line and (' passed' in line or ' failed' in line): marks['end'] = time.monotonic() - start
    try:
        test(udid, app, 'testDemoTour', now, work / 'demo.xcresult', mark)
    finally:
        recorder.send_signal(signal.SIGINT); recorder.wait(timeout=30)
    # Skip runner start-up and app launch; the tour itself starts about 4 s after the test case begins.
    begin = marks.get('begin', 0) + 4.0
    length = max(3.0, marks.get('end', begin + 20) - begin)
    run('ffmpeg', '-loglevel', 'error', '-y', '-ss', f'{begin:.2f}', '-t', f'{length:.2f}', '-i', str(movie),
        '-vf', 'scale=720:-2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(work / 'demo.mp4'))
    frames = work / 'frames'; frames.mkdir(exist_ok=True)
    run('ffmpeg', '-loglevel', 'error', '-y', '-i', str(work / 'demo.mp4'), '-vf', 'fps=10,scale=360:-2:flags=lanczos', str(frames / '%04d.png'))
    images = [Image.open(p).convert('RGB') for p in sorted(frames.glob('*.png'))]
    first, end = app_frames(images)
    images = images[first:end]
    run('ffmpeg', '-loglevel', 'error', '-y', '-ss', f'{first / 10:.1f}', '-i', str(work / 'demo.mp4'), '-t', f'{(end - first) / 10:.1f}',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(work / 'demo-cut.mp4'))
    (work / 'demo-cut.mp4').replace(work / 'demo.mp4')
    images[0].save(out, save_all=True, append_images=images[1:], duration=100, loop=0, quality=62, method=6)


def app_frames(images):
    """(first, end) indexes of the frames that show the app. The walk-through runs in light mode, where every app screen
    is mostly the light background; before launch and after XCTest closes the app (which xcodebuild reports only seconds
    later) the home-screen wallpaper fills the frame instead."""
    def on_app(image):
        pixels = list(image.resize((90, 196)).getdata())
        return sum(1 for r, g, b in pixels if min(r, g, b) > 215 and max(r, g, b) - min(r, g, b) < 25) > 0.25 * len(pixels)
    flags = [on_app(image) for image in images]
    first = flags.index(True) if True in flags else 0
    end = next((i for i in range(first, len(flags)) if not flags[i]), len(flags))
    return first, end


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--device', default='iPhone 17 Pro')
    parser.add_argument('--now', help='frozen destination-local time, default: first trip day 10:30')
    parser.add_argument('--out', type=Path, default=ROOT / 'docs/assets')
    parser.add_argument('--video', action='store_true', help='also record docs/assets/demo.webp')
    args = parser.parse_args()
    trip = json.loads((ROOT / 'ios/TripJournal/Resources/Content/trip.json').read_text())
    now = args.now or trip['startDate'] + 'T10:30'
    udid = device(args.device)
    subprocess.run(['xcrun', 'simctl', 'boot', udid], capture_output=True)  # fails harmlessly if already booted
    run('xcrun', 'simctl', 'bootstatus', udid, '-b', capture_output=True)
    run('xcrun', 'simctl', 'status_bar', udid, 'override', '--time', '9:41', '--dataNetwork', 'wifi', '--wifiMode', 'active',
        '--wifiBars', '3', '--cellularMode', 'active', '--cellularBars', '4', '--batteryState', 'charged', '--batteryLevel', '100')
    run('xcodegen', 'generate', '--spec', str(ROOT / 'ios/project.yml'), '--quiet')
    work = Path(tempfile.mkdtemp(prefix='trip-screenshots-'))
    print(f'building… (work directory {work})')
    run('xcodebuild', 'build-for-testing', '-project', str(PROJECT), '-scheme', 'Screenshots', '-destination', f'id={udid}',
        '-quiet', capture_output=True)
    app = bundle_id()
    (args.out / 'screens').mkdir(parents=True, exist_ok=True)
    shots = {}
    try:
        for mode in ('light', 'dark'):
            print(f'capturing {mode} mode…')
            run('xcrun', 'simctl', 'ui', udid, 'appearance', mode)
            test(udid, app, 'testCaptureScreens', now, work / f'{mode}.xcresult')
            shots[mode] = export(work / f'{mode}.xcresult', work / mode)
            for key, path in shots[mode].items(): single(path, key, mode, args.out / 'screens' / f'{key}-{mode}.jpg')
            hero(shots[mode], trip, mode, args.out / f'hero-{mode}.jpg')
        social(shots['light'], args.out / 'social-preview.png')
        if args.video:
            print('recording demo…')
            run('xcrun', 'simctl', 'ui', udid, 'appearance', 'light')
            video(udid, app, now, work, args.out / 'demo.webp')
            print(f'demo.mp4 for social posts: {work / "demo.mp4"}')
    finally:
        run('xcrun', 'simctl', 'status_bar', udid, 'clear')
        run('xcrun', 'simctl', 'ui', udid, 'appearance', 'light')
    for path in sorted(args.out.rglob('*')):
        if path.is_file(): print(f'{path}  {path.stat().st_size // 1024} KB')


if __name__ == '__main__':
    main()
