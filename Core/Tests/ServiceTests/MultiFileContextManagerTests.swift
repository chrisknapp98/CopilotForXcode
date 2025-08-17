import XCTest

@testable import Service
@testable import Workspace

class MultiFileContextManagerTests: XCTestCase {
    
    var sut: MultiFileContextManager {
        MultiFileContextManager(
            workspaceProvider: WorkspaceProviderMock(),
            parser: SwiftProgrammingLanguageSyntaxParser()
        )
    }
    
//    func testListingFiles() async {
//        let sut = sut
//        let files = await sut.listFilesInWorkspace()
//        
//        XCTAssertNotEqual(files.count, 0)
//    }
    
//    func testRetrievingFileContent() async {
//        let sut = sut
//        let files = await sut.readFileContents()
//        
//        XCTAssertNotEqual(files.count, 0)
//    }
    
//    func testClassifyingCode() async {
//        let sut = sut
//        let classifiedSymbols = await sut.classifyContentWithinFiles()
//        // symbols
//        XCTAssertNotEqual(classifiedSymbols.count, 0)
//    }
    
//    func testScanningForDependencyKeys() async {
//        let sut = sut
//        let dependencyKeys = await sut.scanProjectForDependencyKeys()
//        let registeredDependencies = dependencyKeys.map { dependencyKey in
//            sut.getDependencySymbolsFromExtensionContent(dependencyKey.symbol.content)
//        }
//        XCTAssertNotEqual(dependencyKeys.count, 0)
//    }
}


class WorkspaceProviderMock: WorkspaceProvider {
    func workspace() async throws -> Workspace? {
//        let workspaceURL = URL(filePath: "/Users/christopherknapp/repos/CopilotForXcode-Fork/Copilot for Xcode.xcworkspace")
//        let workspaceURL = URL(filePath: "/Users/christopherknapp/repos/clean-architecture-swiftui-fork")
//        let workspaceURL = URL(filePath: "/Users/christopherknapp/repos/ios-minttv")
//        let workspaceURL = URL(filePath: "/Users/christopherknapp/repos/ios-minttv/Pod/Classes/Twitch/TwitchEndpoint.swift")
//        let workspaceURL = URL(filePath: "/Users/christopherknapp/repos/ios-minttv/Pod/Classes/Twitch/Chat/IRC")
//        let workspaceURL = URL(filePath: "/Users/christopherknapp/repos/ios-minttv/Pod/Classes/Twitch/Chat/Presentation/View")projectRootURL    Foundation.URL    "file:///Users/christopherknapp/repos/ModernCleanArchitectureSwiftUI/"
        let workspaceURL = URL(filePath: "/Users/christopherknapp/repos/ModernCleanArchitectureSwiftUI/")
        return Workspace(workspaceURL: workspaceURL)
    }
    
    func getProjectRootURL() async throws -> URL {
        URL(filePath: "/Users/christopherknapp/repos/ModernCleanArchitectureSwiftUI/")
    }
}

//private func mockFilespace() -> Filespace {
//    let fileURL = URL(filePath: "/Users/christopherknapp/repos/CopilotForXcode-Fork/Core/Sources/Service/SuggestionCommandHandler/PseudoCommandHandler.swift")
//    return Filespace(fileURL: fileURL) { filespace in
//        return
//    } onClose: { url in
//        return
//    }
//
//}
