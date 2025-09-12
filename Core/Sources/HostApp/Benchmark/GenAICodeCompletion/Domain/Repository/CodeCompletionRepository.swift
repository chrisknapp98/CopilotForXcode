protocol CodeCompletionRepository {
    func structuredEdit(for request: SuggestionRequest) async throws -> CodeEdit
}
