import UIKit

final class CredentialPDFGenerator {

    static func generate(credentials: [Credential], userName: String) -> URL? {
        let pageWidth: CGFloat = 612  // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - (margin * 2)

        let pdfURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MedMiles_Credentials_\(userName.replacingOccurrences(of: " ", with: "_")).pdf")

        UIGraphicsBeginPDFContextToFile(pdfURL.path, CGRect.zero, [
            kCGPDFContextTitle as String: "MedMiles Credential Package",
            kCGPDFContextAuthor as String: userName,
        ])

        var yPosition: CGFloat = 0

        func startNewPage() {
            UIGraphicsBeginPDFPageWithInfo(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), nil)
            yPosition = margin
        }

        func checkPageBreak(needed: CGFloat) {
            if yPosition + needed > pageHeight - margin {
                startNewPage()
            }
        }

        // Title attributes
        let titleFont = UIFont.boldSystemFont(ofSize: 22)
        let subtitleFont = UIFont.systemFont(ofSize: 12, weight: .medium)
        let headingFont = UIFont.boldSystemFont(ofSize: 16)
        let captionFont = UIFont.systemFont(ofSize: 9, weight: .regular)

        let titleColor = UIColor(red: 54/255, green: 54/255, blue: 56/255, alpha: 1) // graphite
        let tealColor = UIColor(red: 0, green: 181/255, blue: 165/255, alpha: 1)
        let grayColor = UIColor.gray

        // -- Cover / Header Page --
        startNewPage()

        // App icon + title on same line
        if let appIcon = UIImage(named: "AppIcon") {
            let iconSize: CGFloat = 40
            let iconRect = CGRect(x: margin, y: yPosition, width: iconSize, height: iconSize)
            appIcon.draw(in: iconRect)

            // Title next to icon
            let title = "Credential Package"
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: titleColor]
            title.draw(at: CGPoint(x: margin + iconSize + 10, y: yPosition + 8), withAttributes: titleAttrs)
            yPosition += iconSize + 10
        } else {
            // Fallback if icon not found
            let title = "MedMiles — Credential Package"
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: titleColor]
            title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttrs)
            yPosition += 30
        }

        // User name
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: subtitleFont, .foregroundColor: tealColor]
        userName.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: nameAttrs)
        yPosition += 20

        // Date generated
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        let dateStr = "Generated: \(dateFormatter.string(from: Date()))"
        let dateAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: grayColor]
        dateStr.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: dateAttrs)
        yPosition += 10

        // Count
        let activeCount = credentials.filter { $0.computedStatus != "expired" }.count
        let countStr = "\(activeCount) active credential\(activeCount == 1 ? "" : "s")"
        countStr.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: dateAttrs)
        yPosition += 25

        // Divider line
        let context = UIGraphicsGetCurrentContext()
        context?.setStrokeColor(tealColor.cgColor)
        context?.setLineWidth(1.5)
        context?.move(to: CGPoint(x: margin, y: yPosition))
        context?.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
        context?.strokePath()
        yPosition += 20

        // -- Credentials Summary Table --
        do {
            let summaryHeadingAttrs: [NSAttributedString.Key: Any] = [.font: headingFont, .foregroundColor: titleColor]
            "Credentials Summary".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: summaryHeadingAttrs)
            yPosition += 28

            // Table layout
            let colCredential: CGFloat = contentWidth * 0.30
            let colIssuer: CGFloat = contentWidth * 0.28
            let colExpiration: CGFloat = contentWidth * 0.24
            let colStatus: CGFloat = contentWidth * 0.18
            let rowHeight: CGFloat = 20
            let headerHeight: CGFloat = 22

            // Header row background
            let headerRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: headerHeight)
            context?.setFillColor(UIColor(red: 240/255, green: 240/255, blue: 242/255, alpha: 1).cgColor)
            context?.fill(headerRect)

            // Header text
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: titleColor
            ]
            let headerY = yPosition + 4
            var xOffset = margin + 6
            "Credential".draw(at: CGPoint(x: xOffset, y: headerY), withAttributes: headerAttrs)
            xOffset += colCredential
            "Issuing Body".draw(at: CGPoint(x: xOffset, y: headerY), withAttributes: headerAttrs)
            xOffset += colIssuer
            "Expiration Date".draw(at: CGPoint(x: xOffset, y: headerY), withAttributes: headerAttrs)
            xOffset += colExpiration
            "Status".draw(at: CGPoint(x: xOffset, y: headerY), withAttributes: headerAttrs)
            yPosition += headerHeight

            // Data rows
            let cellFont = UIFont.systemFont(ofSize: 10)
            let cellColor = UIColor.darkGray

            for (index, credential) in credentials.enumerated() {
                checkPageBreak(needed: rowHeight + 4)

                // Alternate row background
                if index % 2 == 0 {
                    let rowRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: rowHeight)
                    context?.setFillColor(UIColor(red: 248/255, green: 248/255, blue: 250/255, alpha: 1).cgColor)
                    context?.fill(rowRect)
                }

                let cellAttrs: [NSAttributedString.Key: Any] = [.font: cellFont, .foregroundColor: cellColor]
                let cellY = yPosition + 4
                var cx = margin + 6

                // Credential type (truncate if needed)
                let credName = credential.credentialType
                let credRect = CGRect(x: cx, y: cellY, width: colCredential - 8, height: rowHeight - 4)
                (credName as NSString).draw(in: credRect, withAttributes: cellAttrs)
                cx += colCredential

                // Issuing body
                let issuer = credential.issuingBody ?? "—"
                let issuerRect = CGRect(x: cx, y: cellY, width: colIssuer - 8, height: rowHeight - 4)
                (issuer as NSString).draw(in: issuerRect, withAttributes: cellAttrs)
                cx += colIssuer

                // Expiration date
                let expText: String
                if let expDate = credential.displayExpirationDate {
                    expText = dateFormatter.string(from: expDate)
                } else {
                    expText = "No Expiration"
                }
                let expRect = CGRect(x: cx, y: cellY, width: colExpiration - 8, height: rowHeight - 4)
                (expText as NSString).draw(in: expRect, withAttributes: cellAttrs)
                cx += colExpiration

                // Status with color
                let statusColor: UIColor
                switch credential.status {
                case "expired":
                    statusColor = UIColor(red: 226/255, green: 75/255, blue: 74/255, alpha: 1)
                case "expiring_soon":
                    statusColor = UIColor(red: 239/255, green: 159/255, blue: 39/255, alpha: 1)
                default:
                    statusColor = UIColor(red: 11/255, green: 138/255, blue: 110/255, alpha: 1)
                }
                let statusCellAttrs: [NSAttributedString.Key: Any] = [.font: cellFont, .foregroundColor: statusColor]
                let statusRect = CGRect(x: cx, y: cellY, width: colStatus - 8, height: rowHeight - 4)
                (credential.statusLabel as NSString).draw(in: statusRect, withAttributes: statusCellAttrs)

                yPosition += rowHeight
            }

            // Divider after summary table
            yPosition += 12
            context?.setStrokeColor(tealColor.cgColor)
            context?.setLineWidth(1.0)
            context?.move(to: CGPoint(x: margin, y: yPosition))
            context?.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
            context?.strokePath()
            yPosition += 20
        }

        // -- Credential Documents --
        // The summary table above is the first-page list of every credential and
        // its expiration date. The pages below hold the actual scanned documents
        // (photos and PDFs), each on its own page and labeled so it can be matched
        // back to the right credential.
        for credential in credentials {
            let docFiles = LocalStorageService.shared.receiptFilenames(for: credential.id)
            guard !docFiles.isEmpty else { continue }

            // Expiration label reused on each of this credential's document pages
            let expLabel: String
            if let expDate = credential.displayExpirationDate {
                expLabel = "Expires: \(dateFormatter.string(from: expDate))"
            } else {
                expLabel = "No Expiration"
            }

            let docHeadingAttrs: [NSAttributedString.Key: Any] = [.font: headingFont, .foregroundColor: titleColor]
            let docSubAttrs: [NSAttributedString.Key: Any] = [.font: subtitleFont, .foregroundColor: tealColor]

            // Draws the credential label (type + issuer + expiration) at the top of
            // a freshly started document page and advances yPosition below it.
            func drawDocumentLabel(extra: String?) {
                credential.credentialType.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: docHeadingAttrs)
                yPosition += 22
                var sub = expLabel
                if let issuer = credential.issuingBody, !issuer.isEmpty {
                    sub = "\(issuer)  •  \(expLabel)"
                }
                if let extra = extra {
                    sub += "  •  \(extra)"
                }
                sub.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: docSubAttrs)
                yPosition += 24
            }

            for filename in docFiles {
                if filename.lowercased().hasSuffix(".pdf") {
                    // Render each page of the attached PDF, one document page each
                    let fileURL = LocalStorageService.shared.receiptURL(filename: filename)
                    if let pdfDoc = CGPDFDocument(fileURL as CFURL) {
                        let pageCount = pdfDoc.numberOfPages
                        for pageIndex in 1...pageCount {
                            guard let pdfPage = pdfDoc.page(at: pageIndex) else { continue }
                            startNewPage()
                            drawDocumentLabel(extra: pageCount > 1 ? "Page \(pageIndex) of \(pageCount)" : nil)

                            // Fit the PDF page into the remaining area
                            let pdfRect = pdfPage.getBoxRect(.mediaBox)
                            let availableWidth = contentWidth
                            let availableHeight = pageHeight - yPosition - margin - 10
                            let scale = min(availableWidth / pdfRect.width, availableHeight / pdfRect.height, 1.0)
                            let scaledWidth = pdfRect.width * scale
                            let scaledHeight = pdfRect.height * scale

                            // Center horizontally
                            let xOffset = margin + (availableWidth - scaledWidth) / 2

                            if let ctx = UIGraphicsGetCurrentContext() {
                                ctx.saveGState()
                                // PDF pages render upside-down by default, so flip the coordinate system
                                ctx.translateBy(x: xOffset, y: yPosition + scaledHeight)
                                ctx.scaleBy(x: scale, y: -scale)
                                ctx.drawPDFPage(pdfPage)
                                ctx.restoreGState()
                            }

                            yPosition += scaledHeight + 8
                        }
                    }
                } else if let image = LocalStorageService.shared.loadReceipt(filename: filename) {
                    // Render the scan/photo on its own page
                    startNewPage()
                    drawDocumentLabel(extra: nil)

                    let maxImgWidth: CGFloat = contentWidth
                    let maxImgHeight: CGFloat = pageHeight - yPosition - margin - 10
                    let imgAspect = image.size.width / image.size.height
                    var imgWidth = maxImgWidth
                    var imgHeight = imgWidth / imgAspect
                    if imgHeight > maxImgHeight {
                        imgHeight = maxImgHeight
                        imgWidth = imgHeight * imgAspect
                    }

                    // Center horizontally
                    let xImg = margin + (maxImgWidth - imgWidth) / 2
                    let imgRect = CGRect(x: xImg, y: yPosition, width: imgWidth, height: imgHeight)
                    image.draw(in: imgRect)
                    yPosition += imgHeight + 8
                }
            }
        }

        // Footer on last page with small logo
        let footerY = pageHeight - margin + 10
        if let appIcon = UIImage(named: "AppIcon") {
            let smallIcon: CGFloat = 14
            appIcon.draw(in: CGRect(x: margin, y: footerY - 2, width: smallIcon, height: smallIcon))
            let footer = "MedMiles — Track it all. Keep what's yours."
            let footerAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: grayColor]
            footer.draw(at: CGPoint(x: margin + smallIcon + 4, y: footerY), withAttributes: footerAttrs)
        } else {
            let footer = "Generated by MedMiles — Track it all. Keep what's yours."
            let footerAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: grayColor]
            footer.draw(at: CGPoint(x: margin, y: footerY), withAttributes: footerAttrs)
        }

        UIGraphicsEndPDFContext()

        return pdfURL
    }
}
