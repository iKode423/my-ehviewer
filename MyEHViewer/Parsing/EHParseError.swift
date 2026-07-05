import Foundation

/// Describes a missing required field while parsing site HTML.
enum EHParseError: LocalizedError, Equatable {
    case missingSearchResultURL
    case missingGalleryIdentifier
    case missingGalleryTitle
    case missingImageURL
    case missingImagePageIdentifier

    var errorDescription: String? {
        switch self {
        case .missingSearchResultURL:
            "搜索结果缺少图库链接。"
        case .missingGalleryIdentifier:
            "图库页面缺少有效标识。"
        case .missingGalleryTitle:
            "图库页面缺少标题。"
        case .missingImageURL:
            "阅读页缺少图片链接。"
        case .missingImagePageIdentifier:
            "阅读页缺少页码标识。"
        }
    }
}

