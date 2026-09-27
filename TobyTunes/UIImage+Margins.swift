//
//  UIImage+Margins.swift
//  TobyTunes
//
//  Created by Toby Nelson on 20/06/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import UIKit
import CoreImage

extension UIImage {
    /// A square thumbnail `side` points across, filled edge to edge (non-square artwork is
    /// cropped to its centre rather than letterboxed). Rounded corners come from the image view.
    func squareThumbnail(side: Int) -> UIImage {
        let size = CGSize(width: CGFloat(side), height: CGFloat(side))
        let scale = max(size.width / max(self.size.width, 1), size.height / max(self.size.height, 1))
        let drawSize = CGSize(width: self.size.width * scale, height: self.size.height * scale)
        let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    func imageWithImage(image:UIImage, scaledToSize newSize:CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let image = renderer.image { _ in
            self.draw(in: CGRect.init(origin: CGPoint.zero, size: newSize))
        }
        return image
    }

    func resize(fitWithinSize withinSize: CGSize) -> UIImage {
        var newSize: CGSize
        let widthScale  = withinSize.width / self.size.width
        let heightScale = withinSize.height / self.size.height

        if widthScale < heightScale {
            newSize = CGSize(width: CGFloat(withinSize.width), height: CGFloat(self.size.height * widthScale) )
        }
        else {
            newSize = CGSize(width: CGFloat(self.size.width * heightScale), height: CGFloat(withinSize.height) )
        }
        return self.imageWithImage(image: self, scaledToSize: newSize)
    }

    func crop(rect: CGRect) -> UIImage? {
        let rect = CGRect(x: rect.origin.x * self.scale,
                          y: rect.origin.y * self.scale,
                          width: rect.size.width * self.scale,
                          height: rect.size.height * self.scale)
        var cgImage : CGImage? = nil
        if self.cgImage != nil {
            cgImage = self.cgImage?.cropping(to: rect)
        }
        else if self.ciImage != nil {
            // Default CIContext renders with Metal (the old OpenGL ES context is deprecated)
            let context = CIContext(options: [CIContextOption.workingColorSpace: NSNull()])
            cgImage = context.createCGImage(self.ciImage!, from: rect)
        }

        if cgImage == nil {
            return nil
        }
        let result = UIImage(cgImage: cgImage!, scale:self.scale, orientation:self.imageOrientation)
        return result
    }

    func imageWithGaussianBlur() -> UIImage? {
        let ciImageOpt = UIKit.CIImage(image: self)
        guard let ciImage = ciImageOpt else { return nil }

        let blurred = ciImage.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 25.0])
        let lowContrast = blurred.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 0.7, kCIInputBrightnessKey: 0.0, kCIInputSaturationKey: 1.0])

        return UIImage(ciImage: lowContrast).crop(rect: ciImage.extent)
    }
}
