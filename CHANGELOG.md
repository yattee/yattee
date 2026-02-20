## What's Changed

### New Features

* Add video proxy support for Invidious/Piped instances

### Bug Fixes

* Fix CFNetwork SIGABRT crash when creating download tasks on invalidated session
* Fix BGTaskScheduler crash by moving registration to App.init()
* Fix Piped relatedStreams decoding crash on missing fields
