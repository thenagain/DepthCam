import UIKit
import ARKit
import RealityKit

class ViewController: UIViewController, ARSessionDelegate {
    
    @IBOutlet var arView: ARView!

    let depthView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        return imageView
    }()

    let rgbView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        return imageView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = .smoothedSceneDepth
        arView.session.run(configuration, options: [])
        arView.session.delegate = self

        rgbView.frame = CGRect(x: 0, y: 0, width: arView.bounds.width, height: arView.bounds.height / 2)
        arView.addSubview(rgbView)

        depthView.frame = CGRect(x: 0, y: arView.bounds.height / 2, width: arView.bounds.width, height: arView.bounds.height / 2)
        arView.addSubview(depthView)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if let depthData = frame.smoothedSceneDepth {
            let depthMap = depthData.depthMap
            let depthImage = CIImage(cvPixelBuffer: depthMap)
            if let filter: CIFilter = CIFilter(name: "CIColorControls", parameters: ["inputContrast": 0.5]) {
                filter.setValue(depthImage.oriented(.right), forKey: kCIInputImageKey)
                if let image = filter.outputImage {
                    let pseudo = PseudoColor()
                    pseudo.inputImage = image
                    depthView.image = UIImage(ciImage: pseudo.outputImage)
                }
            }
        }

        let rgbImage = CIImage(cvPixelBuffer: frame.capturedImage)
        rgbView.image = UIImage(ciImage: rgbImage.oriented(.right))
    }
}

// MARK: PseudoColor
/// This filter isn't dissimilar to Core Image's own False Color filter
/// but it accepts five input colors and uses `mix()` and `smoothstep()`
/// to transition between them based on an image's luminance. The
/// balance between linear and Hermite interpolation is controlled by
/// the `inputSmoothness` parameter.
class PseudoColor: CIFilter
{
    var inputImage: CIImage?

    var inputSmoothness = CGFloat(0.5)

    var inputColor0 = CIColor(red: 1, green: 0, blue: 1)
    var inputColor1 = CIColor(red: 0, green: 0, blue: 1)
    var inputColor2 = CIColor(red: 0, green: 1, blue: 0)
    var inputColor3 = CIColor(red: 1, green: 0, blue: 1)
    var inputColor4 = CIColor(red: 0, green: 1, blue: 1)

    override var attributes: [String : Any]
    {
        return [
            kCIAttributeFilterDisplayName: "Pseudo Color Filter",

            "inputImage": [kCIAttributeIdentity: 0,
                kCIAttributeClass: "CIImage",
                kCIAttributeDisplayName: "Image",
                kCIAttributeType: kCIAttributeTypeImage],

            "inputSmoothness": [kCIAttributeIdentity: 0,
                kCIAttributeClass: "NSNumber",
                kCIAttributeDescription: "Controls interpolation between colors. Range from 0.0 (Linear) to 1.0 (Hermite).",
                kCIAttributeDefault: 0.5,
                kCIAttributeDisplayName: "Smoothness",
                kCIAttributeMin: 0,
                kCIAttributeSliderMin: 0,
                kCIAttributeSliderMax: 1,
                kCIAttributeType: kCIAttributeTypeScalar],

            "inputColor0": [kCIAttributeIdentity: 0,
                kCIAttributeClass: "CIColor",
                kCIAttributeDisplayName: "Color One",
                kCIAttributeDefault: CIColor(red: 1, green: 0, blue: 1),
                kCIAttributeType: kCIAttributeTypeColor],

            "inputColor1": [kCIAttributeIdentity: 0,
                kCIAttributeClass: "CIColor",
                kCIAttributeDisplayName: "Color Two",
                kCIAttributeDefault: CIColor(red: 0, green: 0, blue: 1),
                kCIAttributeType: kCIAttributeTypeColor],

            "inputColor2": [kCIAttributeIdentity: 0,
                kCIAttributeClass: "CIColor",
                kCIAttributeDisplayName: "Color Three",
                kCIAttributeDefault: CIColor(red: 0, green: 1, blue: 0),
                kCIAttributeType: kCIAttributeTypeColor],

            "inputColor3": [kCIAttributeIdentity: 0,
                kCIAttributeClass: "CIColor",
                kCIAttributeDisplayName: "Color Four",
                kCIAttributeDefault: CIColor(red: 1, green: 0, blue: 1),
                kCIAttributeType: kCIAttributeTypeColor],

            "inputColor4": [kCIAttributeIdentity: 0,
                kCIAttributeClass: "CIColor",
                kCIAttributeDisplayName: "Color Five",
                kCIAttributeDefault: CIColor(red: 0, green: 1, blue: 1),
                kCIAttributeType: kCIAttributeTypeColor]
        ]
    }

    let pseudoColorKernel = CIColorKernel(source:
        "vec4 getColor(vec4 color0, vec4 color1, float edge0, float edge1, float luma, float smoothness) \n" +
        "{ \n" +
        "   vec4 smoothColor = color0 + ((color1 - color0) * smoothstep(edge0, edge1, luma)); \n" +
        "   vec4 linearColor = mix(color0, color1, (luma - edge0) * 4.0);  \n" +

        "   return mix(linearColor, smoothColor, smoothness); \n" +
        "} \n" +

        "kernel vec4 pseudoColor(__sample image, float smoothness,  vec4 inputColor0, vec4 inputColor1, vec4 inputColor2, vec4 inputColor3, vec4 inputColor4) \n" +
        "{ \n" +
        "   float luma = dot(image.rgb, vec3(0.2126, 0.7152, 0.0722)); \n" +

        "   if (luma < 0.25) \n" +
        "   { return getColor(inputColor0, inputColor1, 0.0, 0.25, luma, smoothness); } \n" +

        "   else if (luma >= 0.25 && luma < 0.5) \n" +
        "   { return getColor(inputColor1, inputColor2, 0.25, 0.5, luma, smoothness); } \n" +

        "   else if (luma >= 0.5 && luma < 0.75) \n" +
        "   { return getColor(inputColor2, inputColor3, 0.5, 0.75, luma, smoothness); } \n" +

        "   { return getColor(inputColor3, inputColor4, 0.75, 1.0, luma, smoothness); } \n" +
        "}"
    )

    override var outputImage: CIImage!
    {
        guard let inputImage = inputImage,
              let pseudoColorKernel = pseudoColorKernel else
        {
            return nil
        }

        let extent = inputImage.extent
        let arguments = [inputImage, inputSmoothness, inputColor0, inputColor1, inputColor2, inputColor3, inputColor4] as [Any]

        return pseudoColorKernel.apply(extent: extent, arguments: arguments)
    }
}
