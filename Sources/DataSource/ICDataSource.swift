//
//  ICDataSource.swift
//  InfiniteCalevndarView
//
//  Created by Shohe Ohtani on 2022/03/29.
//

import SwiftUI


protocol ICDataSourceDelegate: AnyObject {
    func didUpdateAllDayHeader(view: UICollectionReusableView, kind: String, isExpanded: Bool)
    func didSelectAllDayItem(date: Date, at indexPath: IndexPath)
}

extension ICDataSourceDelegate {
    func didUpdateAllDayHeader(view: UICollectionReusableView, kind: String, isExpanded: Bool) {}
    func didSelectAllDayItem(date: Date, at indexPath: IndexPath) {}
}

open class ICDataSource<View: CellableView, Cell: ViewHostingCell<View>>:
    CollectionDataSource<ICDataProvider<View, Cell>, Cell> {
    
    public var isAllHeaderExpended: Bool = false
    public var vibrateFeedback: UIImpactFeedbackGenerator?
    
    private var currentInitDate: Date!
    private var currentSettings: ICViewSettings!
    
    weak var delegate: ICDataSourceDelegate?
    
    /// Hightlight
    private var hightlighted: ICView.HightlightIndex?
    
    
    override init(parentVC: UIViewController, collectionView: UICollectionView, provider: ICDataProvider<View, Cell>) {
        super.init(parentVC: parentVC, collectionView: collectionView, provider: provider)
        currentSettings = provider.settings
    }
    
    open func updateSettings(_ settings: ICViewSettings) {
        currentSettings = settings
    }
    
    open func updateInitDate(_ initDate: Date) {
        currentInitDate = initDate
    }
    
    open func updateEvents(_ events: [Date: [View.VM]]) {
        provider.events = events
    }
    
    open func hightlightTimeHeader(_ hightlightIndex: ICView.HightlightIndex?) {
        // off current hightlight if needed
        if hightlightIndex?.0 != hightlighted?.0 {
            updateHighlight(item: hightlighted?.0?.item, isOn: false)
            updateHighlight(item: hightlightIndex?.0?.item, isOn: true)
            vibrateFeedback?.impactOccurred(intensity: 0.4)
        }
        if hightlightIndex?.1 != hightlighted?.1 {
            updateHighlight(item: hightlighted?.1?.item, isOn: false)
            updateHighlight(item: hightlightIndex?.1?.item, isOn: true)
            vibrateFeedback?.impactOccurred(intensity: 0.4)
        }
        
        hightlighted = hightlightIndex
    }
    
    open func updateHighlight(item: Int?, isOn: Bool) {
        guard let i = item else { return }
        if let timeHeader = self.collectionView.supplementaryView(forElementKind: ICViewSettings.TimeHeader.className, at: IndexPath(item: i, section: 0)) as? ICViewSettings.TimeHeader {
            if var item = timeHeader.item {
                item.isHighlighted = isOn
                timeHeader.configure(parentVC: parentVC, item: item)
            }
        }
    }
    
    open func allDayHeaderViews(allDayVM: [View.VM]) -> [AnyView] {
        var allDayViews = [AnyView]()
        let itemVerticalMargin: CGFloat = 1.0
        for vm in allDayVM {
            let cell = Cell()
            cell.frame = CGRect(origin: .zero, size: CGSize(
                width: provider.layout.sectionWidth,
                height: provider.layout.defaultAllDayOneLineHeight + (itemVerticalMargin*2)
            ))
            cell.configure(parentVC: parentVC, viewModel: vm)
            guard let v = cell.view else { continue }
            allDayViews.append(AnyView(v))
        }
        return allDayViews
    }
    
    // MARK: - UICollectionViewDataSource
    open override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        var view = UICollectionReusableView()
        
        switch kind {
        case ICViewSettings.TimeHeader.className:
            if let timeHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as? ICViewSettings.TimeHeader {
                let date = provider.layout.date(forTimeHeaderAt: indexPath)
                let range = (provider.settings.timeRange.startTime...provider.settings.timeRange.endTime)
                let item = ICTimeHeaderItem(date: date, isDisplayed: range.contains(date.hour))
                timeHeader.configure(parentVC: parentVC, item: item)
                view = timeHeader
            }
        case ICViewSettings.DateHeader.className:
            if let dateHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as? ICViewSettings.DateHeader {
                let date = provider.layout.date(forTimeHeaderAt: indexPath)
                let item = ICDateHeaderItem(date: date)
                dateHeader.configure(parentVC: parentVC, item: item)
                view = dateHeader
            }
        case ICViewSettings.DateHeaderCorner.className:
            if let cornerHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as? ICViewSettings.DateHeaderCorner {
                cornerHeader.configure(parentVC: parentVC, item: ICContentBackgroundItem())
                view = cornerHeader
            }
        case ICViewSettings.AllDayHeaderCorner.className:
            if let allDayCorner = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as? ICViewSettings.AllDayHeaderCorner {
                let maxItemCount = provider.layout.dates(forInCurrentPage: collectionView, isScrolling: true)
                    .compactMap { provider.allDayEvents[$0]?.count }
                    .max() ?? 0
                let item = ICAllDayCornerItem(itemCount: maxItemCount, isExpended: isAllHeaderExpended) { isExpanded in
                    self.isAllHeaderExpended = isExpanded
                    self.delegate?.didUpdateAllDayHeader(view: allDayCorner, kind: ICAllDayCorner.className, isExpanded: self.isAllHeaderExpended)
                }
                allDayCorner.configure(parentVC: parentVC, item: item)
                view = allDayCorner
            }
        case ICViewSettings.AllDayHeader.className:
            if let allDayHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as? ICViewSettings.AllDayHeader {
                let date = provider.layout.date(forDateHeaderAt: indexPath)
                let vms = provider.allDayEvents[date] ?? []
                let views = allDayHeaderViews(allDayVM: vms)
                let item = ICAllDayHeaderItem(views: views, isExpended: isAllHeaderExpended) { isExpanded in
                    self.isAllHeaderExpended = isExpanded
                    self.delegate?.didUpdateAllDayHeader(view: allDayHeader, kind: ICViewSettings.AllDayHeader.className, isExpanded: self.isAllHeaderExpended)
                }
                allDayHeader.configure(parentVC: parentVC, item: item)
                allDayHeader.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapAllDayItem(gesture:))))
                view = allDayHeader
            }
        case ICViewSettings.Timeline.className:
            if let timeline = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as? ICViewSettings.Timeline {
                let date = provider.layout.date(forTimeHeaderAt: indexPath)
                let item = ICTimelineItem(isDisplayed: date.isToday)
                timeline.configure(parentVC: parentVC, item: item)
                view = timeline
            }
        default: break
        }
        
        return view
    }
    
    // Get item indexPath from tap position
    @objc private func tapAllDayItem(gesture: UITapGestureRecognizer) {
        let cPoint: CGPoint = gesture.location(in: collectionView)
        let sPoint: CGPoint = gesture.location(in: parentVC.view)
        let section: Int = provider.layout.section(forCollectionViewPoint: cPoint, withPointInSelfView: sPoint)
        let date: Date = provider.layout.date(forSection: section)
        
        let tapItemPoint: CGFloat = sPoint.y - provider.layout.dateHeaderHeight
        let itemIndex: Int = Int(tapItemPoint / provider.layout.defaultAllDayOneLineHeight)
        
        if let items = provider.allDayEvents[date], items.count > itemIndex {
            delegate?.didSelectAllDayItem(date: date, at: IndexPath(row: itemIndex, section: section))
        }
    }
}