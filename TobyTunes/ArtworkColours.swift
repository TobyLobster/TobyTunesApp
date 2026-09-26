//
//  ArtworkColours.swift
//  TobyTunes
//
//  Background colours for Now Playing, taken from the album artwork.
//

import UIKit
import CoreImage

enum ArtworkColours {
    /// Fallback when there's no artwork (a deep blue-grey).
    static let defaultGradient: (top: UIColor, bottom: UIColor) = (
        UIColor(red: 0.20, green: 0.29, blue: 0.35, alpha: 1),
        UIColor(red: 0.07, green: 0.10, blue: 0.13, alpha: 1)
    )

    /// Top and bottom colours of a vertical gradient matching `image`. Both are dark enough
    /// for white text to stay readable (brightness at most 0.48 at the top, 0.13 at the bottom).
    /// Safe to call off the main thread.
    static func gradient(for image: UIImage) -> (top: UIColor, bottom: UIColor) {
        guard let average = averageColour(of: image) else { return defaultGradient }

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let sat = min(saturation * 1.1, 0.65)
        let top = UIColor(hue: hue, saturation: sat, brightness: min(max(brightness, 0.30), 0.48), alpha: 1)
        let bottom = UIColor(hue: hue, saturation: sat, brightness: 0.13, alpha: 1)
        return (top, bottom)
    }

    /// The average colour of the whole image.
    static func averageColour(of image: UIImage) -> UIColor? {
        guard let input = CIImage(image: image) else { return nil }
        let extent = CIVector(cgRect: input.extent)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: extent]),
              let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [CIContextOption.workingColorSpace: NSNull()])
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: CIFormat.RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }
}
