import Foundation

enum DateFormatters {
    static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm 'on' EEE, d MMM"
        return formatter
    }()
}
