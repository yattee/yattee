# Yattee Development Notes

## Testing Instances

- **Invidious**: `https://invidious.home.arekf.net/` - Use this instance for testing API calls
- **Yattee Server**: `https://main.s.yattee.stream` - Local self-hosted Yattee server for backend testing

## Related Projects

### Yattee Server

Location: `~/Developer/yattee-server`

A self-hosted API server powered by yt-dlp that provides an Invidious-compatible API for YouTube content. Used as an alternative backend when Invidious/Piped instances are blocked or unavailable.

**Key features:**
- Invidious-compatible API endpoints (`/api/v1/videos`, `/api/v1/channels`, `/api/v1/search`, etc.)
- Uses yt-dlp with deno for YouTube JS challenge solving
- Returns direct YouTube CDN stream URLs
- Optional backing Invidious instance for trending, popular, and search suggestions

**API endpoints:**
- `GET /api/v1/videos/{video_id}` - Video metadata and streams
- `GET /api/v1/channels/{channel_id}` - Channel info
- `GET /api/v1/channels/{channel_id}/videos` - Channel videos
- `GET /api/v1/search?q={query}` - Search
- `GET /api/v1/playlists/{playlist_id}` - Playlist info

**Limitations:**
- No comments support
- Stream URLs expire after a few hours
- Trending/popular/suggestions require backing Invidious instance
- scheme name to build is Yattee. use generic platform build instead of specific sim/device id

## UI Testing with AXe

The project uses a Ruby/RSpec-based UI testing framework with [AXe](https://github.com/cameroncooke/AXe) for simulator automation and visual regression testing.

### Running UI Tests

```bash
# Install dependencies (first time)
bundle install

# Run all UI tests
./bin/ui-test

# Skip build (faster iteration)
./bin/ui-test --skip-build

# Keep simulator running after tests
./bin/ui-test --keep-simulator

# Generate new baseline screenshots
./bin/ui-test --generate-baseline

# Run on a different device
./bin/ui-test --device "iPad Pro 13-inch (M5)"
```

### Creating Tests for New Features

When implementing a new feature, create a UI test to verify it works:

1. **Create a new spec file** in `spec/ui/smoke/`:
   ```ruby
   # spec/ui/smoke/my_feature_spec.rb
   require_relative '../spec_helper'

   RSpec.describe 'My New Feature', :smoke do
     before(:all) do
       @udid = UITest::Simulator.boot(UITest::Config.device)
       UITest::App.build(device: UITest::Config.device, skip: UITest::Config.skip_build?)
       UITest::App.install(udid: @udid)
       UITest::App.launch(udid: @udid)
       sleep UITest::Config.app_launch_wait
       @axe = UITest::Axe.new(@udid)
     end

     after(:all) do
       UITest::App.terminate(udid: @udid, silent: true) if @udid
       UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
     end

     it 'displays the new feature element' do
       # Navigate to the feature if needed
       @axe.tap_label('Settings')
       sleep 1

       # Check for expected elements
       expect(@axe).to have_text('My New Feature')
     end

     it 'matches baseline screenshot', :visual do
       screenshot = @axe.screenshot('my-feature-screen')
       expect(screenshot).to match_baseline
     end
   end
   ```

2. **Available AXe actions:**
   ```ruby
   @axe.tap_label('Button Text')      # Tap by accessibility label
   @axe.tap_id('accessibilityId')     # Tap by accessibility identifier
   @axe.tap_coordinates(x: 100, y: 200)
   @axe.swipe(start_x: 200, start_y: 400, end_x: 200, end_y: 100)
   @axe.gesture('scroll-down')        # Presets: scroll-up, scroll-down, scroll-left, scroll-right
   @axe.type('search text')           # Type text
   @axe.home_button                   # Press home
   @axe.screenshot('name')            # Take screenshot
   ```

3. **Available matchers:**
   ```ruby
   expect(@axe).to have_element('AXUniqueId')  # Check by accessibility identifier
   expect(@axe).to have_text('Visible Text')   # Check by accessibility label
   expect(screenshot_path).to match_baseline   # Visual comparison (2% threshold)
   ```

4. **Run with baseline generation:**
   ```bash
   ./bin/ui-test --generate-baseline --keep-simulator
   ```

5. **Inspect accessibility tree** to find element identifiers:
   ```bash
   # Boot simulator and launch app first, then:
   axe describe-ui --udid <SIMULATOR_UDID>
   ```

### Directory Structure

```
spec/
├── ui/
│   ├── spec_helper.rb           # RSpec configuration
│   ├── support/
│   │   ├── config.rb            # Test configuration
│   │   ├── simulator.rb         # Simulator management
│   │   ├── app.rb               # App build/install/launch
│   │   ├── axe.rb               # AXe CLI wrapper
│   │   ├── axe_matchers.rb      # Custom RSpec matchers
│   │   └── screenshot_comparison.rb
│   └── smoke/
│       └── app_launch_spec.rb   # Example test
└── ui_snapshots/
    ├── baseline/                # Reference screenshots (by device/iOS version)
    │   └── iPhone_17_Pro/
    │       └── iOS_26_2/
    │           └── app-launch-library.png
    ├── current/                 # Current test run screenshots
    ├── diff/                    # Visual diff images
    └── false_positives.yml      # Mark expected differences
```

### Tips

- Use `have_text` matcher for most checks - it's more reliable than `have_element` since iOS doesn't always expose accessibility identifiers
- Add `sleep 1` after navigation actions to let UI settle
- Use `--keep-simulator` during development to speed up iteration
- Check `spec/ui_snapshots/diff/` for visual diff images when tests fail
- Add entries to `false_positives.yml` for screenshots with expected dynamic content
