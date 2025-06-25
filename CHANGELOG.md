## 0.1.0

* **FEATURE**: Added support for pull-to-action at both top and bottom edges of scrollable widgets
* **NEW API**: Introduced `pullDownCustomIndicators` and `pullUpCustomIndicators` properties for direction-specific customization
* **NEW API**: Added `pullDownTargetIndicator` and `pullUpTargetIndicator` properties for direction-specific target indicators  
* **BREAKING**: Deprecated `customIndicators` property in favor of the new direction-specific properties
* **ENHANCEMENT**: Improved drag cancellation logic to properly handle scroll-back operations
* **ENHANCEMENT**: Enhanced test coverage with comprehensive test cases for new bidirectional functionality

## 0.0.3

* Improved the armed state detection logic to stabilize behavior in the test environment 
* Removed unnecessary casts in the test code

## 0.0.2

* Improved the _updateTargetPositionXByDragX method to calculate the absolute position based on the relative movement from the scroll start point.

## 0.0.1

* alpha initial release!🙌
