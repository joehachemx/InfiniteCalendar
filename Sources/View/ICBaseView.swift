//
//  ICBaseView.swift
//  InfiniteCalendarView
//
//  Created by Shohe Ohtani on 2022/03/23.
//

import UIKit
import SwiftUI


open class ICBaseView<View: CellableView, Cell: ViewHostingCell<View>>: UIView, UICollectionViewDelegate {
    
    var collectionView: ICCollectionView!
    var parentViewController: UIViewController!
    var layout: ICViewFlowLayout!
    var dataSource: ICDataSource<View, Cell>?
    var initDate: Date = Date() {
        didSet {
            layout.updateInitDate(initDate)
            dataSource?.updateInitDate(initDate)
        }
    }
    var settings: ICViewSettings = ICViewSettings() {
        didSet {
            layout.updateSettings(settings)
            dataSource?.updateSettings(settings)
        }
    }
    
    var vibrateFeedback: UIImpactFeedbackGenerator?
    
    public private (set) var allDayEvents = [Date: [View.VM]]()
    public private (set) var events = [Date: [View.VM]]()
    public private (set) var currentDate: Date = Date()
    
    private let preparePages: Int = 15
    private var currentDateWorkItem: DispatchWorkItem?
    private var allDayHeaderWorkItem: DispatchWorkItem?
    
    public weak var delegate: ICBaseViewDelegate<View,Cell>?
    
    var contentViewWidth: CGFloat {
        return frame.width - layout.timeHeaderWidth - layout.contentsMargin.left - layout.contentsMargin.right
    }
    
    
    // Params for Scroll ---
    var scrollDirection: ScrollDirection?
    
    var contentOffsetRange: ClosedRange<CGFloat> {
        let maxContentOffsetY: CGFloat =
            collectionView.contentSize.height -
            collectionView.bounds.height +
            collectionView.contentInset.bottom
        return (0...maxContentOffsetY)
    }
    
    /// Use for section pagination
    private typealias Velocity = CGPoint
    private typealias DestinationOffset = (CGPoint, Velocity)
    private var destinationOffset: DestinationOffset?
    private var maxVerticalScrollRange: ClosedRange<CGFloat> {
        return -layout.allDayHeaderHeight...layout.maxSectionHeight - layout.allDayHeaderHeight - collectionView.frame.height
    }
    
    /// Use for page pagination
    var scrollType: ScrollType { return settings.scrollType }
    var pageWidth: CGFloat {
        return (scrollType == .sectionScroll) ? layout.sectionWidth : contentViewWidth
    }
    private var currentTappedPage: Int?
    
    
    public init(parentViewController: UIViewController) {
        super.init(frame: parentViewController.view.bounds)
        setup(with: parentViewController)
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup(with: UIViewController())
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(with: UIViewController())
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        layout.sectionWidth = getSectionWidth()
        layout.invalidateLayoutCache()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.collectionView.reloadData()
            self.updateAllDayBar(isScrolling: false, isExpended: self.dataSource?.isAllHeaderExpended ?? false)
        }
    }
    
    open override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let p = superview?.convert(point, to: collectionView) {
            let fixedX: CGFloat = p.x - (layout.timeHeaderWidth + layout.contentsMargin.left + layout.contentsMargin.right)
            // If tapped TimeHeader add one page, because it's previous page area
            let isTouchTimeHeader = (p.x <= layout.timeHeaderWidth)
            let tappedPage: Int = Int(fixedX / pageWidth)
            self.currentTappedPage = isTouchTimeHeader ? tappedPage+1 : tappedPage
        }
        return super.hitTest(point, with: event)
    }
    
    open func setup(with parentVC: UIViewController) {
        parentViewController = parentVC
        
        layout = ICViewFlowLayout(settings: settings)
        layout.delegate = self
        
        collectionView = ICCollectionView(frame: bounds, collectionViewLayout: layout)
        collectionView.delegate = self
        collectionView.isDirectionalLockEnabled = false
        collectionView.bounces = true
        collectionView.showsVerticalScrollIndicator = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .white
        addSubview(collectionView)
        collectionView.setAnchorConstraintsFullSizeTo(view: self)
        
        registerViewClasses()
    }
    
    open func updateAllDayBar(isScrolling: Bool, isExpended: Bool) {
        var maxEventCount: Int = 0
        
        layout.dates(forInCurrentPage: collectionView, isScrolling: isScrolling).forEach {
            let count = allDayEvents[$0]?.count ?? 0
            if count > maxEventCount {
                maxEventCount = count
            }
        }
        
        let eventCount: Int = isExpended ? maxEventCount : min(maxEventCount, 3)
        let newAllDayHeader = layout.defaultAllDayOneLineHeight * CGFloat(eventCount)
        
        // Check whether it needs to update the allDayHeaderHeight
        if newAllDayHeader != layout.allDayHeaderHeight {
            layout.allDayHeaderHeight = newAllDayHeader
            collectionView.contentInset.top = newAllDayHeader
            collectionView.contentInset.bottom = layout.contentsMargin.bottom - newAllDayHeader
            collectionView.verticalScrollIndicatorInsets.top = layout.dateHeaderHeight + newAllDayHeader
            collectionView.reloadData()
        }
    }
    
    open func pagePaginationEffect(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        var destination: DestinationOffset = getNearestDestinationOffset(scrollView, velocity: velocity, destinationOffset: targetContentOffset.pointee)
        
        if let tappedPage = currentTappedPage {
            let targetPage = (velocity.x > 0) ? tappedPage+1 : tappedPage-1
            destination = (CGPoint(x: CGFloat(targetPage)*pageWidth, y: scrollView.contentOffset.y), velocity)
        }
        
        // if scrolling direction with velocity is already out of range, reset paging offset.
        let scrollableRange: ClosedRange<CGFloat> = getScrollableRange()
        if !scrollableRange.contains(destination.0.x) {
            let offset: CGPoint = getPointeeResetedPagingOffset(scrollView, withVelocity: velocity)
            destination.0 = offset
        }
        targetContentOffset.pointee = destination.0
    }
    
    open func sectionPaginationEffect(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        var destination: DestinationOffset = getNearestDestinationOffset(scrollView, velocity: velocity, destinationOffset: targetContentOffset.pointee)
        
        // if scrolling direction with velocity is already out of range, reset paging offset.
        let scrollableRange: ClosedRange<CGFloat> = getScrollableRange()
        if !scrollableRange.contains(destination.0.x) {
            let offset: CGPoint = getPointeeResetedPagingOffset(scrollView, withVelocity: velocity)
            destination.0 = offset
        }
        
        destinationOffset = destination
        targetContentOffset.pointee = destination.0
    }
    
    open func endOfScroll() {
        scrollDirection = nil
        destinationOffset = nil
        
        allDayHeaderWorkItem?.cancel()
        allDayHeaderWorkItem = DispatchWorkItem {
            self.updateAllDayBar(isScrolling: false, isExpended: self.dataSource?.isAllHeaderExpended ?? false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+0.1, execute: allDayHeaderWorkItem!)
    }
    
    open func forceReload() {
        DispatchQueue.main.async {
            if let targetOffset = self.destinationOffset {
                self.collectionView.setContentOffset(targetOffset.0, velocity: targetOffset.1, timingFunction: .quadOut) { [weak self] in
                    guard let strongSelf = self else { return }
                    strongSelf.endOfScroll()
                }
            } else {
                let paging = PagingDirection(self.collectionView)
                let velocity = (paging.scrollingTo == .stay) ? .zero : CGPoint(x: paging.scrollingTo == .next ? 1 : -1, y: 0)
                self.getPointeeResetedPagingOffset(self.collectionView, withVelocity: velocity)
                self.endOfScroll()
            }
        }
    }
    
    
    /// Setup method for ISCalendarView, it **must** be called.
    /// - Parameters:
    ///     - numOfDays: Number of days in a page
    ///     - settings: Default settings
    public func setupCalendar(events: [View.VM], settings: ICViewSettings) {
        setupEvents(events)
        self.settings = settings
        initDate = initDateForCollectionView(settings.initDate)
        
        let provider = ICDataProvider<View, Cell>(
            layout: layout,
            allDayEvents: allDayEvents,
            events: self.events,
            settings: settings,
            preparePages: preparePages
        )
        dataSource = ICDataSource(parentVC: parentViewController, collectionView: collectionView, provider: provider)
        dataSource?.delegate = self
        
        if settings.withVibrateFeedback {
            vibrateFeedback = UIImpactFeedbackGenerator(style: .rigid)
            dataSource?.vibrateFeedback = vibrateFeedback
        }
        
        DispatchQueue.main.async { [unowned self] in
            self.layoutSubviews()
            
            // setup center position
            let middlePage: Int = Int(preparePages/2)
            let middlePageOffsetX: CGFloat = self.contentViewWidth*CGFloat(middlePage)
            self.collectionView.contentOffset.x += middlePageOffsetX
        }
    }

    public func updateEvents(_ events: [View.VM]) {
        setupEvents(events)
        DispatchQueue.main.async { [unowned self] in
            self.layoutSubviews()
        }
    }
    
    public func updateSettings(_ settings: ICViewSettings) {
        self.settings = settings
    }
    
    public func resetCollectionViewOffset(by date: Date, animated: Bool) {
        guard let sectionWidth = layout.sectionWidth else { return }
        
        initDate = initDateForCollectionView(date)
        let fixedDate: Date = getFirstDayOfWeek(setDate: date.startOfDay, firstDayOfWeek: .Sunday)
        let section = Date.daysBetween(start: initDate, end: fixedDate, ignoreHours: true)
        
        let offsetY = layout.offset(forCurrentTimeline: collectionView).y
        collectionView.setContentOffset(CGPoint(x: CGFloat(section) * sectionWidth, y: offsetY), animated: animated)
        currentDate = date.startOfDay
        delegate?.didUpdateCurrentDate(currentDate)
        endOfScroll()
    }
    
    public func registerViewClasses() {
        // supplementary
        collectionView.registerSupplementaryViews([
            ICViewSettings.TimeHeader.self,
            ICViewSettings.DateHeader.self,
            ICViewSettings.DateHeaderCorner.self,
            ICViewSettings.AllDayHeader.self,
            ICViewSettings.AllDayHeaderCorner.self,
            ICViewSettings.Timeline.self,
        ])
        
        // decoration
        layout.registerDecorationViews([
            ICViewSettings.DateHeaderBackground.self,
            ICViewSettings.TimeHeaderBackground.self,
            ICViewSettings.AllDayHeaderBackground.self
        ])
        layout.register(ICGridLine.self, forDecorationViewOfKind: ICViewKinds.Decoration.verticalGridline)
        layout.register(ICGridLine.self, forDecorationViewOfKind: ICViewKinds.Decoration.horizontalGridline)
        
        // eventCell
        collectionView.register(Cell.self, forCellWithReuseIdentifier: Cell.reuseIdentifier)
    }
    
    
    // MARK: - UICollectionViewDelegate
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollDirection = getBegginDraggingScrollDirection()
        guard let direction = scrollDirection else { return }

        // deceleration rate should be normal in vertical scroll
        scrollView.decelerationRate = (direction.direction == .horizontal) ? .fast : .normal
    }
    
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard let scrollDirection = self.scrollDirection else { return }

        switch scrollDirection.direction {
        case .vertical:
            if let lockedAt = scrollDirection.lockedAt { scrollView.contentOffset.x = lockedAt }
        case .horizontal:
            if let lockedAt = scrollDirection.lockedAt { scrollView.contentOffset.y = lockedAt }
            guard abs(velocity.x) > 0 else { return }
            switch scrollType {
            case .pageScroll:
                pagePaginationEffect(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
            case .sectionScroll:
                sectionPaginationEffect(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
            }
        default: break
        }
    }
    
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // handle the situation scrollViewDidEndDragging not being called
        if !decelerate {
            let duration: TimeInterval = (scrollType == .pageScroll) ? 0.3 : 0.15
            scrollView.setContentOffset(getNearestDestinationOffset(scrollView).0, duration: duration, timingFunction: .quadOut) { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.endOfScroll()
            }
        }

        // Wait 0.3 sec for make sure scroll is done
        guard scrollDirection?.direction == .horizontal else { return }
        currentDateWorkItem?.cancel()
        currentDateWorkItem = DispatchWorkItem {
            self.currentDate = self.layout.date(forCollectionViewAt: self.convert(CGPoint(x: self.layout.timeHeaderWidth, y: scrollView.contentOffset.y), to: scrollView))
            self.delegate?.didUpdateCurrentDate(self.currentDate)
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+0.3, execute: currentDateWorkItem!)
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        endOfScroll()
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollDirection == nil { scrollDirection = getBegginDraggingScrollDirection() }
        
        switch scrollDirection?.direction {
        case .vertical:
            if let lockedAt = scrollDirection?.lockedAt { scrollView.contentOffset.x = lockedAt }
        case .horizontal:
            if let lockedAt = scrollDirection?.lockedAt { scrollView.contentOffset.y = lockedAt }
        default: break
        }

        // When scrolling over than range of visible view, update initDate
        if !getScrollableRange().contains(scrollView.contentOffset.x) {
            forceReload()
        }

        // When layout.sectionWidth is nil, ignore updateAllDayBar
        guard layout.sectionWidth != nil else { return }

        // TODO: checkScrollableRange()
        updateAllDayBar(isScrolling: true, isExpended: dataSource?.isAllHeaderExpended ?? false)
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let date = layout.date(forDateHeaderAt: indexPath)
        guard let event = events[date]?[indexPath.row] else { return }
        delegate?.didSelectItem(event)
    }
    
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        // If needed implement
    }
}


// MARK: - Private
extension ICBaseView {
    private func getFirstDayOfWeek(setDate: Date, firstDayOfWeek: WeekDay?) -> Date {
        guard let firstDayOfWeek = firstDayOfWeek, settings.numOfDays == 7 else { return setDate.startOfDay }
        let setDayOfWeek = setDate.getDayOfWeek()
        var diff = setDayOfWeek.rawValue - firstDayOfWeek.rawValue
        if diff < 0 { diff = 7 - abs(diff) }
        return setDate.startOfDay.add(component: .day, value: -diff)
    }
    
    private func initDateForCollectionView(_ date: Date) -> Date {
        var _date = date
        if settings.numOfDays == 7 {
            _date = getFirstDayOfWeek(setDate: settings.initDate, firstDayOfWeek: .Sunday)
        }
        return _date.startOfDay.add(component: .day, value: -settings.numOfDays * (preparePages/2))
    }
    
    /// Was going to use toDecimal1Value as well, but the CGFloat is always got the wrong precision
    /// In order to make sure the width of all sections is the same, add few points to CGFloat
    private func getSectionWidth() -> CGFloat {
        var sectionWidth = contentViewWidth / CGFloat(settings.numOfDays)
        let remainder = sectionWidth.truncatingRemainder(dividingBy: 1)
        
        switch remainder {
        case 0...0.25:
            sectionWidth = sectionWidth.rounded(.down)
        case 0.25...0.75:
            sectionWidth = sectionWidth.rounded(.down) + 0.5
        default:
            sectionWidth = sectionWidth.rounded(.up)
        }
        
        // Maximum added width for row header should be 0.25 * numberOfRows
        let timeHeaderWidth = frame.width - layout.contentsMargin.left - layout.contentsMargin.right - sectionWidth * CGFloat(settings.numOfDays)
        layout.timeHeaderWidth = timeHeaderWidth
        return sectionWidth
    }
    
    private func getDateForContentOffsetX(_ contentOffsetX: CGFloat) -> Date {
        let adjustedX = contentOffsetX - layout.contentsMargin.left
        let section = Int(adjustedX / layout.sectionWidth)
        return getDateForSection(section)
    }
    
    private func getDateForSection(_ section: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: section, to: initDate)!
    }
    
    private func setupEvents(_ newEvents: [View.VM]) {
        allDayEvents.removeAll()
        events.removeAll()
        
        for (date, items) in ICViewHelper.getIntraEventsByDate(events: newEvents) {
            allDayEvents[date] = items.filter({$0.isAllDay})
            events[date] = items.filter({!$0.isAllDay})
        }
        
        dataSource?.updateEvents(events)
    }
    
    
    
    // MARK: Pagenation logic
    private func getBegginDraggingScrollDirection() -> ScrollDirection? {
        let velocity = collectionView.panGestureRecognizer.velocity(in: collectionView)
        
        // When velocity is .zero, return same value as current scrollDirection
        if velocity == .zero {
            return scrollDirection
        } else if abs(velocity.x) >= abs(velocity.y) {
            var offsetY: CGFloat = collectionView.contentOffset.y
            if maxVerticalScrollRange.lowerBound > offsetY {
                offsetY = maxVerticalScrollRange.lowerBound
            } else if maxVerticalScrollRange.upperBound < offsetY {
                offsetY = maxVerticalScrollRange.upperBound
            }
            return ScrollDirection(direction: .horizontal, lockedAt: offsetY)
        } else {
            let offsetX: CGFloat = getNearestDestinationOffset(collectionView).0.x
            return ScrollDirection(direction: .vertical, lockedAt: offsetX)
        }
    }
    
    private func getNearestDestinationOffset(_ scrollView: UIScrollView, velocity: CGPoint = .zero, destinationOffset: CGPoint? = nil) -> DestinationOffset {
        // When scroll type is .pageScroll, destination date is next date
        var destinationX: CGFloat = (scrollType == .pageScroll) ? scrollView.contentOffset.x : (destinationOffset?.x ?? scrollView.contentOffset.x)
        var destinationDate: Date = getDateForContentOffsetX(destinationX)
        
        if scrollType == .pageScroll {
            let isVelocitySatisfied = abs(velocity.x) > 0.4
            if isVelocitySatisfied {
                destinationDate = destinationDate.add(component: .day, value: (velocity.x > 0) ? 1 : 0)
            } else {
                destinationDate = getFirstDayOfWeek(setDate: destinationDate, firstDayOfWeek: .Sunday)
                guard let diff: Int = Calendar.current.dateComponents([.day], from: initDate, to: destinationDate).day else { fatalError() }
                
                // if scrolled less than half of previous page, stay current date
                if CGFloat(diff) * layout.sectionWidth + pageWidth/2 <= destinationX {
                    destinationDate = destinationDate.add(component: .day, value: settings.numOfDays)
                }
            }
        }
        
        guard let diff: Int = Calendar.current.dateComponents([.day], from: initDate, to: destinationDate).day else { fatalError() }
        
        // if offset.x is more than half of the target date, it'll be next date
        if scrollType == .pageScroll {
            destinationX = CGFloat(diff / settings.numOfDays) * pageWidth
            // if user scrolled in a row, destination page is going to be increased
            if let lastTargetOffsetX = self.destinationOffset?.0.x, lastTargetOffsetX == destinationX, abs(velocity.x) > 0 {
                destinationX = (velocity.x > 0) ? destinationX+pageWidth : destinationX-pageWidth
            }
        } else {
            destinationX = (CGFloat(diff) * pageWidth + pageWidth / 2 <= destinationX) ? CGFloat(diff+1) * pageWidth : CGFloat(diff) * pageWidth
        }
        
        let pointee = CGPoint(x: destinationX, y: scrollView.contentOffset.y)
        return (pointee, velocity)
    }
    
    private func getScrollableRange() -> ClosedRange<CGFloat> {
        let rightUpdateOffsetX = (contentViewWidth * CGFloat(preparePages-1)) - (contentViewWidth / 2)
        let leftUpdateOffsetX = contentViewWidth / 2
        return leftUpdateOffsetX...rightUpdateOffsetX
    }
    
    /**
     * Get paging offset after reset current scrollView offset to middle page.
     */
    @discardableResult
    private func getPointeeResetedPagingOffset(_ scrollView: UIScrollView, withVelocity velocity: CGPoint) -> CGPoint {
        let middlePage: Int = Int(preparePages/2)
        let middlePageOffsetX: CGFloat = self.contentViewWidth*CGFloat(middlePage)
        
        if abs(velocity.x) > 0 {
            if velocity.x > 0 {
                scrollView.contentOffset.x -= self.contentViewWidth*CGFloat(middlePage)
                self.resetInitialDate(.next)
            } else {
                scrollView.contentOffset.x += self.contentViewWidth*CGFloat(middlePage)
                self.resetInitialDate(.previous)
            }
        }
        
        return CGPoint(x: middlePageOffsetX, y: scrollView.contentOffset.y)
    }
    
    public func resetInitialDate(_ pagingDirection: PagingDirection.Direction) {
        switch pagingDirection {
        case .next:
            let additionalDate = settings.numOfDays*Int(preparePages/2)
            initDate = initDate.add(component: .day, value: additionalDate)
        case .previous:
            let additionalDate = -settings.numOfDays*Int(preparePages/2)
            initDate = initDate.add(component: .day, value: additionalDate)
        case .stay: break
        }
        
        updateAllDayBar(isScrolling: false, isExpended: dataSource?.isAllHeaderExpended ?? false)
        layout.invalidateLayoutCache()
        collectionView.reloadData()
    }
    
    /// Notice: A temporary solution to fix the scroll from bottom issue when isScrolling
    /// The issue is because the decreased height value will cause the system to change the collectionView contentOffset, but the affected contentOffset will
    /// greater than the contentSize height, and the view will show some abnormal updates, this value will be used with isScrolling to check whether the in scroling change will be applied
    private func willEffectContentSize(difference: CGFloat) -> Bool {
        return collectionView.contentOffset.y + difference + collectionView.bounds.height > collectionView.contentSize.height
    }
}


// MARK: - ICViewFlowLayoutDelegate
extension ICBaseView: ICViewFlowLayoutDelegate {
    public func collectionView(_ collectionView: UICollectionView, layout: ICViewFlowLayout, dayForSection section: Int) -> Date {
        return getDateForSection(section)
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout: ICViewFlowLayout, startTimeForItemAtIndexPath indexPath: IndexPath) -> Date {
        let date = layout.date(forDateHeaderAt: indexPath)
        
        if let events = events[date] {
            return events[indexPath.item].intraStartDate
        } else {
            print("Connot get events at \(date)")
            return Date()
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout: ICViewFlowLayout, endTimeForItemAtIndexPath indexPath: IndexPath) -> Date {
        let date = layout.date(forDateHeaderAt: indexPath)
        
        if let events = events[date] {
            return events[indexPath.item].intraEndDate
        } else {
            print("Connot get events at \(date)")
            return Date()
        }
    }
}


// MARK: - ICDataSourceDelegate
extension ICBaseView: ICDataSourceDelegate {
    func didUpdateAllDayHeader(view: UICollectionReusableView, kind: String, isExpanded: Bool) {
        updateAllDayBar(isScrolling: false, isExpended: isExpanded)
    }
    
    func didSelectAllDayItem(date: Date, at indexPath: IndexPath) {
        let date = layout.date(forDateHeaderAt: indexPath)
        guard let events = allDayEvents[date], events.count > indexPath.row else { return }
        delegate?.didSelectItem(events[indexPath.row])
    }
}