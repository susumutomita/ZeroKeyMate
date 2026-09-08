import SwiftUI
import XCTest
@testable import ZeroKeyMate

@MainActor
final class EyeAppearanceTests:XCTestCase {
    func testConversationStatesRemainVisuallyDistinctWithReducedMotion() throws {
        var renders:[Data]=[]
        for (name,hearing,thinking,speaking) in [("hearing",true,false,false),("thinking",false,true,false),("speaking",false,false,true)] {
            let view=MateEyes(resting:false,listening:hearing,thinking:thinking,focus:0,verticalFocus:0,reduceMotion:true,speaking:speaking,hearingSpeech:hearing)
                .frame(width:304,height:240).frame(width:390,height:500)
                .background(Color(red:0.958,green:0.954,blue:0.937))
            let renderer=ImageRenderer(content:view);renderer.scale=2
            let image=try XCTUnwrap(renderer.uiImage)
            renders.append(try XCTUnwrap(image.pngData()))
            let attachment=XCTAttachment(image:image);attachment.name="eyes-state-"+name;attachment.lifetime = .keepAlways;add(attachment)
        }
        XCTAssertNotEqual(renders[0],renders[1])
        XCTAssertNotEqual(renders[1],renders[2])
        XCTAssertNotEqual(renders[0],renders[2])
    }
    func testRenderEyePositionsForVisualReview() throws {
        for (name,x,y) in [("center",0.0,0.0),("left-up",-0.8,-0.6),("right-down",0.8,0.6)] {
            // Component render with explicit positions; this is not evidence of camera tracking.
            let view=MateEyes(resting:false,listening:false,thinking:false,focus:x,verticalFocus:y,reduceMotion:true)
                .frame(width:304,height:240).frame(width:390,height:700)
                .background(Color(red:0.958,green:0.954,blue:0.937))
            let renderer=ImageRenderer(content:view)
            renderer.scale=2
            let image=try XCTUnwrap(renderer.uiImage)
            let attachment=XCTAttachment(image:image)
            attachment.name="eyes-component-"+name;attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
