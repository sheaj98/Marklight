//
//  MarklightTextStorage
//
//  Created by Matteo Gavagnin on 01/01/16.
//  Copyright © 2016 MacTeo. LICENSE for details.
//

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

extension NSString {
    func paragraphRange(at location: Int) -> NSRange {
        return paragraphRange(for: NSRange(location: location, length: 0))
    }
}

/**
    `NSTextStorage` subclass that uses `Marklight` to highlight markdown syntax
    on a `UITextView`.
    In your `UIViewController` subclass keep a strong instance of the this
    `MarklightTextStorage` class.
    ```swift
    let textStorage = MarklightTextStorage()
    ```
 
    Customise the appearance as desired:

    * Dynamic text style.
    * Markdown syntax color.
    * Code's font and color.
    * Quotes' font and color.
 
    As per Apple's documentation it should be enough to assign the
    `UITextView`'s `NSLayoutManager` to the `NSTextStorage` subclass, in our
    case `MarklightTextStorage`.
 
    ```swift
     textStorage.addLayoutManager(textView.layoutManager)
    ```
    However I'm experiencing some crashes if I want to preload some text instead
    of letting the user start from scratch with a new text. A workaround is 
    proposed below.
    
    For simplicity we assume you have a `String` to be highlighted inside an
    editable `UITextView` loaded from a storyboard.

    ```swift
    let string = "# My awesome markdown string"
    ```

    Convert `string` to an `NSAttributedString`

    ```swift
    let attributedString = NSAttributedString(string: string)
    ```
 
    Set the loaded string to the `UITextView`

    ```swift
    textView.attributedText = attributedString
    ```
 
    Append the loaded string to the `NSTextStorage`

    ```swift
    textStorage.appendAttributedString(attributedString)
    ```
 
    For more informations on how to implement your own `NSTextStorage` subclass,
    follow Apple's official documentation.
 
    - see: [`NSTextStorage`](xcdoc://?url=developer.apple.com/library/ios/documentation/UIKit/Reference/NSTextStorageDelegate_Protocol_TextKit/index.html#//apple_ref/swift/intf/c:objc(pl)NSTextStorage)
    - see: `Marklight`
 */

open class MarklightTextStorage: NSTextStorage {

    /// Delegate from this class cluster to a regular `NSTextStorage` instance
    /// because it does some additional performance optimizations 
    /// over `NSMutableAttributedString`.
    fileprivate let imp = NSTextStorage()
    
    // MARK: Syntax highlight customisation
    
    /**
    Color used to highlight markdown syntax. Default value is light grey.
    */
    open var syntaxColor = MarklightColor.lightGray
    
    /**
     Font used for blocks and inline code. Default value is *Menlo*.
     */
    open var codeFontName = "Menlo"
    
    /**
     `MarklightColor` used for blocks and inline code. Default value is dark grey.
     */
    open var codeColor = MarklightColor.darkGray
    
    /**
     Font used for quote blocks. Default value is *Menlo*.
     */
    open var quoteFontName = "Menlo"
    
    /**
     `MarklightColor` used for quote blocks. Default value is dark grey.
     */
    open var quoteColor = MarklightColor.darkGray
    
    /**
     Quote indentation in points. Default 20.
     */
    open var quoteIndendation : CGFloat = 20
   
    /**
     If the markdown syntax should be hidden or visible
     */
    open var hideSyntax = false
        
    // MARK: Syntax highlighting

    /// Switch used to prevent `processEditing` callbacks from 
    /// within `processEditing`.
    fileprivate var isBusyProcessing = false

    /**
    To customise the appearance of the markdown syntax highlights you should
     subclass this class (or create your own direct `NSTextStorage` subclass)
     and set the customisations in this method implementation. Sends out
     `-textStorage:willProcessEditing`, fixes the attributes, sends out
     `-textStorage:didProcessEditing`, and notifies the layout managers of
     change with the
     `-processEditingForTextStorage:edited:range:changeInLength:invalidatedRange:`
     method.  Invoked from `-edited:range:changeInLength:` or `-endEditing`.
    
    - see:
    [`NSTextStorage`](xcdoc://?url=developer.apple.com/library/ios/documentation/UIKit/Reference/NSTextStorage_Class_TextKit/index.html#//apple_ref/doc/uid/TP40013282)
    */
    override open func processEditing() {

        self.isBusyProcessing = true
        defer { self.isBusyProcessing = false }

        let editedAndAdjacentParagraphRange = self.editedAndAdjacentParagraphRange
        let editedParagraphRange = self.editedParagraphRange
        defer {
            // Include surrounding paragraphs in layout manager's styling pass
            // after finishing the real edit. Mostly needed for Setex headings.
            layoutManagers.first?.processEditing(
                for: self,
                edited: .editedAttributes,
                range: editedRange,
                changeInLength: 0,
                invalidatedRange: editedAndAdjacentParagraphRange)
        }

        resetMarklightAttributes(range: editedAndAdjacentParagraphRange)
//        removeParagraphAttributes()
//        removeWholeAttributes()

        Marklight.syntaxColor = syntaxColor
        Marklight.codeFontName = codeFontName
        Marklight.codeColor = codeColor
        Marklight.quoteFontName = quoteFontName
        Marklight.quoteColor = quoteColor
        Marklight.quoteIndendation = quoteIndendation
        Marklight.textSize = textSize
        Marklight.hideSyntax = hideSyntax
        
        Marklight.processEditing(self, affectedRange: editedAndAdjacentParagraphRange)

        super.processEditing()
    }

    fileprivate var editedParagraphRange: NSRange {
        return (self.string as NSString).paragraphRange(for: self.editedRange)
    }

    fileprivate var editedAndAdjacentParagraphRange: NSRange {
        let textStorageNSString = (self.string as NSString)
        let editedParagraphRange = textStorageNSString.paragraphRange(for: self.editedRange)

        let previousParagraphRange: NSRange
        if editedParagraphRange.location > 0 {
            previousParagraphRange = textStorageNSString.paragraphRange(at: editedParagraphRange.location - 1)
        } else {
            previousParagraphRange = NSRange(location: editedParagraphRange.location, length: 0)
        }

        let nextParagraphRange: NSRange
        let locationAfterEditedParagraph = editedParagraphRange.location + editedParagraphRange.length
        if locationAfterEditedParagraph < textStorageNSString.length {
            nextParagraphRange = textStorageNSString.paragraphRange(at: locationAfterEditedParagraph + 1)
        } else {
            nextParagraphRange = NSRange.init(location: 0, length: 0)
        }

        return NSRange(
            location: previousParagraphRange.location,
            length: [previousParagraphRange, editedParagraphRange, nextParagraphRange].map { $0.length }.reduce(0, +))
    }

    fileprivate func resetMarklightAttributes(range: NSRange) {
        imp.removeAttribute(NSForegroundColorAttributeName, range: range)
        imp.addAttribute(NSFontAttributeName, value: MarklightFont.systemFont(ofSize: textSize), range: range)
        imp.addAttribute(NSParagraphStyleAttributeName, value: NSParagraphStyle(), range: range)
    }

    // Remove every attribute the the paragraph containing the last edit.
    fileprivate func removeParagraphAttributes() {
        let paragraphRange = (string as NSString).paragraphRange(for: self.editedRange)
        resetMarklightAttributes(range: paragraphRange)
    }

    // Remove every attribute to the whole text
    fileprivate func removeWholeAttributes() {
        let wholeRange = NSMakeRange(0, (self.string as NSString).length)
        resetMarklightAttributes(range: wholeRange)
    }


    // MARK: Reading Text
    
    /**
    Use this method to extract the text from the `UITextView` as plain text.
    
    - returns: The `String` containing the text inside the `UITextView`.
    
    - see:
    [`NSTextStorage`](xcdoc://?url=developer.apple.com/library/ios/documentation/UIKit/Reference/NSTextStorage_Class_TextKit/index.html#//apple_ref/doc/uid/TP40013282)
     */
    override open var string : String {
        return imp.string
    }
    
    /**
    Returns the attributes for the character at a given index.
    The attributes for the character at index.
     
    - parameter index: The index for which to return attributes. This value must
      lie within the bounds of the receiver.
     - parameter aRange: Upon return, the range over which the attributes and
       values are the same as those at index. This range isn’t necessarily the
       maximum range covered, and its extent is implementation-dependent. If you
       need the maximum range, use
       attributesAtIndex:longestEffectiveRange:inRange:. If you don't need this
       value, pass NULL.
     - returns: The attributes for the character at index.     - see:
     [`NSTextStorage`](xcdoc://?url=developer.apple.com/library/ios/documentation/UIKit/Reference/NSTextStorage_Class_TextKit/index.html#//apple_ref/doc/uid/TP40013282)
     */

    
    open override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [String : Any] {
        return imp.attributes(at: location, effectiveRange: range)
    }
    
    // MARK: Text Editing
    
    /**
    Replaces the characters in the given range with the characters of the given
     string. The new characters inherit the attributes of the first replaced
     character from aRange. Where the length of aRange is 0, the new characters
     inherit the attributes of the character preceding aRange if it has any,
     otherwise of the character following aRange. Raises an NSRangeException if
     any part of aRange lies beyond the end of the receiver’s characters.
    - parameter aRange: A range specifying the characters to replace.
    - parameter aString: A string specifying the characters to replace those in
       aRange.
    - see:
    [`NSTextStorage`](xcdoc://?url=developer.apple.com/library/ios/documentation/UIKit/Reference/NSTextStorage_Class_TextKit/index.html#//apple_ref/doc/uid/TP40013282)
    */
    override open func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        imp.replaceCharacters(in: range, with: str)
        edited([.editedCharacters], range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }
    
    /**
    Sets the attributes for the characters in the specified range to the 
    specified attributes. These new attributes replace any attributes previously
    associated with the characters in aRange. Raises an NSRangeException if any
    part of aRange lies beyond the end of the receiver’s characters. To set
    attributes for a zero-length NSMutableAttributedString displayed in a text
    view, use the NSTextView method setTypingAttributes:.
     - parameter attributes: A dictionary containing the attributes to set. 
       Attribute keys can be supplied by another framework or can be custom ones
       you define. For information about where to find the system-supplied
       attribute keys, see the overview section in NSAttributedString Class
       Reference.
     - parameter aRange: The range of characters whose attributes are set.
     - see: 
        [`NSMutableAttributedString`](xcdoc://?url=developer.apple.com/library/ios/documentation/Cocoa/Reference/Foundation/Classes/NSMutableAttributedString_Class/index.html#//apple_ref/swift/cl/c:objc(cs)NSMutableAttributedString
     )
     - see:
        [`NSTextStorage`](xcdoc://?url=developer.apple.com/library/ios/documentation/UIKit/Reference/NSTextStorage_Class_TextKit/index.html#//apple_ref/doc/uid/TP40013282)
     */
    
    
    open override func setAttributes(_ attrs: [String : Any]?, range: NSRange) {
        // When we are processing, using the regular callback triggers will 
        // result in the caret jumping to the end of the document.
        guard !isBusyProcessing else {
            imp.setAttributes(attrs, range: range)
            return
        }

        beginEditing()
        imp.setAttributes(attrs, range: range)
        edited([.editedAttributes], range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - iOS-Only Font Text Style Support

    #if os(iOS)

    // MARK: Initialisers

    /**
     The designated initialiser. If you subclass `MarklightTextStorage`, you
     must call the super implementation of this method.
     */
    override public init() {
        super.init()
        observeTextSize()
    }

    /**
     The designated initialiser. If you subclass `MarklightTextStorage`, you must
     call the super implementation of this method.
     */
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        observeTextSize()
    }

    /**
     Internal method to register to notifications determined by dynamic type size
     changes and redraw the attributed text with the appropriate text size.
     Currently it works only after the user adds or removes some chars inside the
     `UITextView`.
     */
    func observeTextSize() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIContentSizeCategoryDidChange, object: nil, queue: OperationQueue.main) { (notification) -> Void in
            let wholeRange = NSMakeRange(0, (self.string as NSString).length)
            self.invalidateAttributes(in: wholeRange)
            for layoutManager in self.layoutManagers {
                layoutManager.invalidateDisplay(forCharacterRange: wholeRange)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Font Style Settings

    /**
     Dynamic type font text style, default `UIFontTextStyleBody`.

     - see: [Text Styles](xcdoc://?url=developer.apple.com/library/ios/documentation/UIKit/Reference/UIFontDescriptor_Class/index.html#//apple_ref/doc/constant_group/Text_Styles)
     */
    open var fontTextStyle : String = UIFontTextStyle.body.rawValue

    /// Text size measured in points.
    fileprivate var textSize: CGFloat {
        return MarklightFontDescriptor
            .preferredFontDescriptor(withTextStyle: UIFontTextStyle(rawValue: self.fontTextStyleValidated))
            .pointSize
    }

    // We are validating the user provided fontTextStyle `String` to match the
    // system supported ones.
    fileprivate var fontTextStyleValidated : String {

        let supportedTextStyles: [String] = {

            let baseStyles = [
                UIFontTextStyle.headline.rawValue,
                UIFontTextStyle.subheadline.rawValue,
                UIFontTextStyle.body.rawValue,
                UIFontTextStyle.footnote.rawValue,
                UIFontTextStyle.caption1.rawValue,
                UIFontTextStyle.caption2.rawValue
            ]

            guard #available(iOS 9.0, *) else { return baseStyles }

            return baseStyles.appending(contentsOf: [
                UIFontTextStyle.title1.rawValue,
                UIFontTextStyle.title2.rawValue,
                UIFontTextStyle.title3.rawValue,
                UIFontTextStyle.callout.rawValue
                ])
        }()

        guard supportedTextStyles.contains(self.fontTextStyle) else {
            return UIFontTextStyle.body.rawValue
        }
        
        return self.fontTextStyle
    }

    #elseif os(macOS)

    open var textSize: CGFloat = NSFont.systemFontSize()

    #endif
}
