import Foundation
import Workspace
import XcodeInspector

protocol WorkspaceProvider {
    func workspace() async throws -> Workspace?
}

class XcodeInspectorWorkspaceProvider: WorkspaceProvider {
    private func getFileURL() async -> URL? {
        await XcodeInspector.shared.safe.realtimeActiveDocumentURL
    }

    @WorkspaceActor
    private func getFilespace() async -> Filespace? {
        guard
            let fileURL = await getFileURL(),
            let (_, filespace) = try? await Service.shared.workspacePool
                .fetchOrCreateWorkspaceAndFilespace(fileURL: fileURL)
        else { return nil }
        return filespace
    }
    
    func workspace() async throws -> Workspace? {
        guard let filespace = await getFilespace() else { return nil }
        let workspacePool: WorkspacePool = await Service.shared.workspacePool
        let tuple: (workspace: Workspace, _: Filespace)? = try await workspacePool.fetchOrCreateWorkspaceAndFilespace(fileURL: filespace.fileURL)
        return tuple?.workspace
    }
}
