// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 drel4
#pragma once
#include <stdbool.h>

// Adapted from DroidSB/Sources/DSBTransientGeometry.h. Match UIRectEdge without
// UIKit so the orientation/corner cases can also be checked outside SpringBoard.
enum { LQSEdgeTop = 1, LQSEdgeLeft = 2, LQSEdgeBottom = 4, LQSEdgeRight = 8 };
static inline unsigned LQSDisplayTopEdge(bool landscape, bool upsideDown,
                                         double fixedTouchX, double fixedMidX) {
    if (!landscape) return upsideDown ? LQSEdgeBottom : LQSEdgeTop;
    return fixedTouchX < fixedMidX ? LQSEdgeLeft : LQSEdgeRight;
}
