# Shortcuts for the common tasks; each target only runs the scripts documented in README.md.
# Override the simulator with: make test SIM="iPhone 17"
SIM ?= iPhone 17 Pro
PROJECT := ios/TripJournal.xcodeproj
DEST := platform=iOS Simulator,name=$(SIM)

.PHONY: setup content project open test screenshots privacy

setup:  ## one-time: Pillow, XcodeGen check, simulator signing config
	@python3 -c "import PIL" 2>/dev/null || python3 -m pip install Pillow
	@command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
	@[ -f ios/Signing.xcconfig ] || cp ios/Signing.example.xcconfig ios/Signing.xcconfig

content:  ## validate content/ and build it into the app bundle
	python3 scripts/verify_content.py
	python3 scripts/build_ios_resources.py

project: content  ## generate the Xcode project from ios/project.yml
	xcodegen generate --spec ios/project.yml

open: project  ## open in Xcode, then run on an iPhone simulator
	open $(PROJECT)

test: project  ## content pipeline, backend, deploy and iOS tests
	python3 -m unittest discover -s scripts -p 'test_*.py'
	python3 -m unittest discover -s server -p 'test_*.py'
	python3 -m unittest discover -s deploy -p 'test_*.py'
	xcodebuild test -project $(PROJECT) -scheme TripJournal -destination '$(DEST)' -quiet

screenshots: project  ## README / sharing images of your trip into docs/assets/
	python3 scripts/make_screenshots.py --device '$(SIM)' --video

privacy:  ## scan the working tree and git history before publishing
	python3 scripts/privacy_check.py --history
