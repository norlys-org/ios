//
//  norlysWidgetBundle.swift
//  norlysWidget
//
//  Created by Hugo on 10.03.2025.
//

import WidgetKit
import SwiftUI

@main
struct norlysWidgetBundle: WidgetBundle {
    var body: some Widget {
        WebcamWidget()
        RTSWWidget()
        RTSWMediumWidget()
        LysWidget()
        NorlysPositionWidget()
    }
}
