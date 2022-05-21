//
//  ICTimeHeader.swift
//  InfiniteCalendarView
//
//  Created by Shohe Ohtani on 2022/03/23.
//

import UIKit
import SwiftUI


// MARK: Foreground
public final class ICTHeader: ViewHostingSupplementaryCell<ICTHeaderView> {}

public struct ICTHeaderView: ICComponentView {
    public typealias Item = ICTimeHeaderItem
    var item: Item
    var isJustTime: Bool { return item.isDisplayed && item.date.minute == 0 }
    
    public init(_ item: Item) {
        self.item = item
    }
    
    public var body: some View {
        HStack {
            Text("\(item.date.hour):\(String(format: "%02d", item.date.minute))")
                .font(.system(size: 12))
                .foregroundColor(item.isHighlighted ? .blue : Color.black.opacity(0.6))
            Spacer().frame(width: 8.0)
            Rectangle()
                .foregroundColor(Color.gray.opacity(0.3))
                .frame(width: 8.0, height: 1.0)
                .offset(y: -0.05)
                .opacity(isJustTime ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .opacity(isJustTime || item.isHighlighted ? 1 : 0)
    }
}


// MARK: Background
public final class ICTHeaderBackground: ViewHostingDecorationCell<ICTHeaderBackgroundView> {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup(item: ICContentBackgroundItem())
    }
}

public struct ICTHeaderBackgroundView: ICComponentView {
    public typealias Item = ICContentBackgroundItem
    var item: Item
    
    public init(_ item: Item) {
        self.item = item
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            item.color
            Rectangle()
                .frame(width: 0.5)
                .foregroundColor(Color.gray.opacity(0.3))
        }
    }
}
