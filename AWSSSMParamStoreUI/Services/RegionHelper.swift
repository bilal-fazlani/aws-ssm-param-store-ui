import Foundation

struct RegionGroup: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let regions: [String]
}

struct RegionHelper {
    static let shared = RegionHelper()
    
    // Hardcoded for now, will be dynamic later
    private let rawRegions = [
        "us-east-1", "us-east-2", "us-west-1", "us-west-2",
        "eu-west-1", "eu-central-1", "eu-west-2", "eu-west-3", "eu-north-1",
        "ap-south-1", "ap-northeast-1", "ap-northeast-2", "ap-southeast-1", "ap-southeast-2",
        "ca-central-1", "sa-east-1"
    ]
    
    var groupedRegions: [RegionGroup] {
        let groups = Dictionary(grouping: rawRegions) { region -> String in
            if region.starts(with: "us") { return "United States" }
            if region.starts(with: "eu") { return "Europe" }
            if region.starts(with: "ap") { return "Asia Pacific" }
            if region.starts(with: "ca") { return "Canada" }
            if region.starts(with: "sa") { return "South America" }
            return "Other"
        }
        
        let sortOrder = ["United States", "Europe", "Asia Pacific", "Canada", "South America", "Other"]
        
        return sortOrder.compactMap { name in
            guard let regions = groups[name] else { return nil }
            return RegionGroup(name: name, regions: regions.sorted())
        }
    }
    
    func regionName(_ code: String) -> String {
        // Simple mapping for display
        switch code {
        case "us-east-1": return "US East (N. Virginia)"
        case "us-east-2": return "US East (Ohio)"
        case "us-west-1": return "US West (N. California)"
        case "us-west-2": return "US West (Oregon)"
        case "eu-west-1": return "Europe (Ireland)"
        case "eu-central-1": return "Europe (Frankfurt)"
        case "eu-west-2": return "Europe (London)"
        case "eu-west-3": return "Europe (Paris)"
        case "eu-north-1": return "Europe (Stockholm)"
        case "ap-south-1": return "Asia Pacific (Mumbai)"
        case "ap-northeast-1": return "Asia Pacific (Tokyo)"
        case "ap-northeast-2": return "Asia Pacific (Seoul)"
        case "ap-southeast-1": return "Asia Pacific (Singapore)"
        case "ap-southeast-2": return "Asia Pacific (Sydney)"
        case "ca-central-1": return "Canada (Central)"
        case "sa-east-1": return "South America (São Paulo)"
        default: return code
        }
    }
}

