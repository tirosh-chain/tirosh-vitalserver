import SwiftUI

enum RuntimeVitalPresentationTypography {
    static let supportingPointSize: CGFloat = 14
    static let panelTitlePointSize: CGFloat = 20
    static let summaryLabelPointSize: CGFloat = 16
    static let summaryValuePointSize: CGFloat = 22
    static let tableHeaderPointSize: CGFloat = 16
    static let tableValuePointSize: CGFloat = 18
    static let tableSecondaryPointSize: CGFloat = 14
    static let detailValuePointSize: CGFloat = 18
    static let sectionTitlePointSize: CGFloat = 17
    static let identityPointSize: CGFloat = 24
    static let statusPointSize: CGFloat = 20

    static let supporting = Font.system(size: supportingPointSize)
    static let panelTitle = Font.system(size: panelTitlePointSize)
    static let summaryLabel = Font.system(size: summaryLabelPointSize)
    static let summaryValue = Font.system(size: summaryValuePointSize)
    static let tableHeader = Font.system(size: tableHeaderPointSize)
    static let tableValue = Font.system(size: tableValuePointSize)
    static let tableSecondary = Font.system(size: tableSecondaryPointSize)
    static let detailValue = Font.system(size: detailValuePointSize)
    static let sectionTitle = Font.system(size: sectionTitlePointSize)
    static let identity = Font.system(size: identityPointSize)
    static let status = Font.system(size: statusPointSize)
}
