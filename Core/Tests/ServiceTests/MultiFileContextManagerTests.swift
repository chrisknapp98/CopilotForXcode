import XCTest

@testable import Service
@testable import Workspace

class MultiFileContextManagerTests: XCTestCase {
    
    var sut: MultiFileContextManager {
        MultiFileContextManager(
            workspaceProvider: WorkspaceProviderMock()
        )
    }
    
    func testListingFiles() async {
        let sut = sut
        let files = await sut.listFilesInWorkspace()
        
        XCTAssertNotEqual(files.count, 0)
    }
    
    func testRetrievingFileContent() async {
        let sut = sut
        let files = await sut.readFileContents()
        
        XCTAssertNotEqual(files.count, 0)
    }
    
    func testClassifyingCode() async {
        let sut = sut
        let classifiedSymbols = await sut.classifyContentWithinFile()
        // symbols
        XCTAssertNotEqual(classifiedSymbols.count, 0)
    }
}


class WorkspaceProviderMock: WorkspaceProvider {
    func workspace() async throws -> Workspace? {
//        let workspaceURL = URL(fileURLWithPath: "/Users/christopherknapp/repos/CopilotForXcode-Fork/Copilot for Xcode.xcworkspace")
//        let workspaceURL = URL(fileURLWithPath: "/Users/christopherknapp/repos/clean-architecture-swiftui-fork")
//        let workspaceURL = URL(fileURLWithPath: "/Users/christopherknapp/repos/ios-minttv")
//        let workspaceURL = URL(fileURLWithPath: "/Users/christopherknapp/repos/ios-minttv/Pod/Classes/Twitch/TwitchEndpoint.swift")
//        let workspaceURL = URL(fileURLWithPath: "/Users/christopherknapp/repos/ios-minttv/Pod/Classes/Twitch/Chat/IRC")
        let workspaceURL = URL(fileURLWithPath: "/Users/christopherknapp/repos/ios-minttv/Pod/Classes/Twitch/Chat/Presentation/View")
        return Workspace(workspaceURL: workspaceURL)
    }
}

//private func mockFilespace() -> Filespace {
//    let fileURL = URL(fileURLWithPath: "/Users/christopherknapp/repos/CopilotForXcode-Fork/Core/Sources/Service/SuggestionCommandHandler/PseudoCommandHandler.swift")
//    return Filespace(fileURL: fileURL) { filespace in
//        return
//    } onClose: { url in
//        return
//    }
//
//}
