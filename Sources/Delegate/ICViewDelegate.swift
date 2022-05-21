//
//  InfiniteCalendarViewDelegate.swift
//  InfiniteCalendarView
//
//  Created by Shohe Ohtani on 2022/04/11.
//

import UIKit
import SwiftUI

public protocol ICViewDelegateProvider: ICBaseViewDelegateProvider {
    func icView(_ icView: ICView<View,Cell>, didAdd event: View.VM, startAt startDate: Date, endAt endDate: Date)
    func icView(_ icView: ICView<View,Cell>, didMove event: View.VM, startAt startDate: Date, endAt endDate: Date)
    func icView(_ icView: ICView<View,Cell>, didCancel event: View.VM, startAt startDate: Date, endAt endDate: Date)
}

open class ICViewDelegate<View: CellableView, Cell: ViewHostingCell<View>>: ICBaseViewDelegate<View, Cell>, ICViewDelegateProvider {
    private let didAddEvent: (ICView<View,Cell>, View.VM, Date, Date) -> Void
    private let didMoveEvent: (ICView<View,Cell>, View.VM, Date, Date) -> Void
    private let didCancelEvent: (ICView<View,Cell>, View.VM, Date, Date) -> Void
    
    init<Provider: ICViewDelegateProvider>(_ delegate: Provider) where Provider.View == View, Provider.Cell == Cell {
        didAddEvent = delegate.icView(_:didAdd:startAt:endAt:)
        didMoveEvent = delegate.icView(_:didMove:startAt:endAt:)
        didCancelEvent = delegate.icView(_:didCancel:startAt:endAt:)
        
        super.init(delegate)
    }
    
    public func icView(_ icView: ICView<View, Cell>, didAdd event: View.VM, startAt startDate: Date, endAt endDate: Date) {
        didAddEvent(icView, event, startDate, endDate)
    }
    
    public func icView(_ icView: ICView<View, Cell>, didMove event: View.VM, startAt startDate: Date, endAt endDate: Date) {
        didMoveEvent(icView, event, startDate, endDate)
    }
    
    public func icView(_ icView: ICView<View, Cell>, didCancel event: View.VM, startAt startDate: Date, endAt endDate: Date) {
        didCancelEvent(icView, event, startDate, endDate)
    }
}
