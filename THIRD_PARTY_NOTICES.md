# Third-Party Notices

SaneVideo is developed by SaneApps and licensed under PolyForm Shield 1.0.0.
This file documents third-party software used by SaneVideo.

## Swift Package dependencies

SaneVideo uses Swift Package Manager. Package sources currently resolved include:

- https://github.com/FluidInference/FluidAudio (Apache License 2.0)
- https://github.com/sparkle-project/Sparkle (MIT)

SaneVideo also uses the SaneApps package https://github.com/sane-apps/SaneUI.

### FluidAudio
- Repository: https://github.com/FluidInference/FluidAudio
- License: Apache License 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
- Use: runs the speech model for captions, silence and filler-word cleanup on your Mac.

### Parakeet TDT 0.6B v3 speech model
- Model: NVIDIA parakeet-tdt-0.6b-v3 (https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3),
  Core ML conversion by FluidInference (https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)
- License: Creative Commons Attribution 4.0 (https://creativecommons.org/licenses/by/4.0/)
- Not bundled with the app. SaneVideo downloads it once (about 600 MB) the first time you make captions or
  run Clean Up, and runs it locally. Apple's on-device speech engine can be chosen instead in Settings.

### Sparkle (explicit MIT notice)
- Repository: https://github.com/sparkle-project/Sparkle
- License: MIT

Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesinski.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Dependency source of truth
- `SaneVideo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
