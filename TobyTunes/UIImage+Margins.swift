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
    func imageWithBorders(width: Int, height: Int) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        UIGraphicsBeginImageContextWithOptions(CGSize(width: rect.width, height: rect.height), true, 0)
        //let context = UIGraphicsGetCurrentContext()
        //let colour = CGColorCreate(CGColorSpaceCreateDeviceRGB(), [1.0, 1.0, 1.0, 1.0])
        //CGContextClearRect(context, rect)
        //CGContextSetFillColorWithColor(context, UIColor.clearColor().CGColor)
        //CGContextFillRect(context, rect)
        UIColor.white.setFill()
        UIRectFill(rect)

        var newRect: CGRect
        if self.size.width > self.size.height {
            let newHeight = Int(CGFloat(height) * self.size.height / self.size.width)
            newRect = CGRect(x: 0, y: (height - newHeight) / 2, width: width, height: newHeight)
        }
        else {
            let newWidth = Int(CGFloat(width) * self.size.width / self.size.height)
            newRect = CGRect(x: (width - newWidth) / 2, y: 0, width: newWidth, height: height)
        }
        self.draw(in: newRect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage!
    }

    func oldImageWithGaussianBlur() -> UIImage {
        let weight = [0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162]

        // Blur horizontally
        UIGraphicsBeginImageContext(self.size)
        self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height), blendMode:CGBlendMode.plusLighter, alpha:CGFloat(weight[0]) )
        for x in 1..<5 {
            self.draw( in: CGRect(x: CGFloat(x), y: 0, width: self.size.width, height: self.size.height), blendMode:CGBlendMode.plusLighter, alpha:CGFloat(weight[x]) )
            self.draw( in: CGRect(x: CGFloat(-x), y: 0, width: self.size.width, height: self.size.height), blendMode:CGBlendMode.plusLighter, alpha:CGFloat(weight[x]) )
        }
        let horizBlurredImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        // Blur vertically
        UIGraphicsBeginImageContext(self.size)
        horizBlurredImage?.draw( in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height), blendMode:CGBlendMode.plusLighter, alpha:CGFloat(weight[0]) )
        for y in 1..<5 {
            horizBlurredImage?.draw( in: CGRect(x: 0, y: CGFloat(y), width: self.size.width, height: self.size.height), blendMode:CGBlendMode.plusLighter, alpha:CGFloat(weight[y]) )
            horizBlurredImage?.draw( in: CGRect(x: 0, y: CGFloat(-y), width: self.size.width, height: self.size.height), blendMode:CGBlendMode.plusLighter, alpha:CGFloat(weight[y]) )
        }
        let blurredImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return blurredImage!
    }

    func imageWithImage(image:UIImage, scaledToSize newSize:CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0);
        image.draw(in: CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height))
        let newImage:UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return newImage
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
            let openGLContext = EAGLContext(api: .openGLES3)
            let context = CIContext(eaglContext: openGLContext!, options:convertToOptionalCIContextOptionDictionary([convertFromCIContextOption(CIContextOption.workingColorSpace): NSNull()]))
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

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToOptionalCIContextOptionDictionary(_ input: [String: Any]?) -> [CIContextOption: Any]? {
	guard let input = input else { return nil }
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (CIContextOption(rawValue: key), value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromCIContextOption(_ input: CIContextOption) -> String {
	return input.rawValue
}
