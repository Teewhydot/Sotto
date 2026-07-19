//
//  ViewState.swift
//  Sotto
//

import Foundation

enum ViewState<T: Equatable>: Equatable {
    case initial
    case loading
    case loaded(T)
    case empty
    case error(AppError)

    var value: T? {
        if case .loaded(let val) = self {
            return val
        }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
