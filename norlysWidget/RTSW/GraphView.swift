//
//  GraphView.swift
//  norlys
//
//  Created by Hugo Lageneste on 11/03/2025.
//

import SwiftUI
import Charts

// DataPoint represents a single data point in the graph.
struct DataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

// GraphDataSeries represents a series of data points with a specific color and label.
struct GraphDataSeries: Identifiable {
    let id = UUID()
    let label: String
    let data: [DataPoint]
    let color: Color
}

// ReusableGraphView is a reusable chart view that plots multiple data series.
// Parameters:
// - dataSeries: Array of data series to plot.
// - zeroLine: Whether to draw a horizontal zero line.
// - verticalMarkerDate: Optional date to draw a vertical marker line (e.g., earth hit marker).
// - chartDomain: The time range for the x-axis.
// - yDomain: The range for the y-axis.
struct ReusableGraphView: View {
    let dataSeries: [GraphDataSeries]
    let zeroLine: Bool
    let verticalMarkerDate: Date?
    let chartDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    
    var body: some View {
        Chart {
            // Draw a horizontal zero line if required.
            if zeroLine {
                RuleMark(
                    y: .value("Zero", 0)
                )
                .foregroundStyle(.gray.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1))
            }
            
            // Draw a vertical marker if a marker date is provided.
            if let markerDate = verticalMarkerDate {
                RuleMark(
                    x: .value("Marker", markerDate)
                )
                .foregroundStyle(.white)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2,2]))
            }
            
            // Plot each data series.
            ForEach(dataSeries) { series in
                ForEach(series.data) { point in
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value(series.label, point.value)
                    )
                    .foregroundStyle(series.color)
                    .symbol(.circle)
                    .symbolSize(3)
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: chartDomain)
    }
}
