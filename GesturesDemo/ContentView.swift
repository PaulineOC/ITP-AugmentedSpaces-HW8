//
//  ContentView.swift
//  GesturesDemo
//
//  Created by Nien Lam on 9/29/21.
//

import SwiftUI
import ARKit
import RealityKit
import Combine
import CoreAudio



// MARK: - View model for handling communication between the UI and ARView.
class ViewModel: ObservableObject {
    let uiSignal = PassthroughSubject<UISignal, Never>()
    
    @Published var anchorSet = false

    enum UISignal {
        case resetAnchor
        case spin
    }
}


// MARK: - UI Layer.
struct ContentView : View {
    @StateObject var viewModel: ViewModel
    
    var body: some View {
        ZStack {
            // AR View.
            ARViewContainer(viewModel: viewModel)
            /*
        
            // Reset button.
            Button {
                viewModel.uiSignal.send(.resetAnchor)
            } label: {
                Label("Reset", systemImage: "gobackward")
                    .font(.system(.title))
                    .foregroundColor(.white)
                    .labelStyle(IconOnlyLabelStyle())
                    .frame(width: 44, height: 44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
            
            
            // Spin button.
            Button {
                viewModel.uiSignal.send(.spin)
            } label: {
                Label("Reset", systemImage: "goforward")
                    .font(.system(.title))
                    .foregroundColor(.white)
                    .labelStyle(IconOnlyLabelStyle())
                    .frame(width: 44, height: 44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding()
             
             */
        }
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
    }
}


// MARK: - AR View.
struct ARViewContainer: UIViewRepresentable {
    let viewModel: ViewModel
    
    func makeUIView(context: Context) -> ARView {
        SimpleARView(frame: .zero, viewModel: viewModel)
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

class SimpleARView: ARView {
    var viewModel: ViewModel
    var arView: ARView { return self }
    var subscriptions = Set<AnyCancellable>()
    var recorder: AVAudioRecorder!
    
    let rotationGestureSpeed: Float = 0.01

    var planeAnchor: AnchorEntity?
    
//   var blades: PinWheelBlades!
     var pinwheels: ModelEntity!
    var stick: Entity!
    
    var lastUpdateTime = Date()
    
    var audioController: AudioPlaybackController!
    
    var isAudioPlaying = false
    var hasBeenTriggered = false
    let threshold: Float = -6.0

    init(frame: CGRect, viewModel: ViewModel) {
        self.viewModel = viewModel
        super.init(frame: frame)
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        setupMicrophoneSensor()
        
        setupScene()
        
        setupEntities()
    }
    
    func setupMicrophoneSensor() {
            let documents = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0])
            let url = documents.appendingPathComponent("record.caf")

            let recordSettings: [String: Any] = [
                AVFormatIDKey:              kAudioFormatAppleIMA4,
                AVSampleRateKey:            44100.0,
                AVNumberOfChannelsKey:      2,
                AVEncoderBitRateKey:        12800,
                AVLinearPCMBitDepthKey:     16,
                AVEncoderAudioQualityKey:   AVAudioQuality.max.rawValue
            ]

            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(AVAudioSession.Category.playAndRecord)
                try audioSession.setActive(true)
                try recorder = AVAudioRecorder(url:url, settings: recordSettings)
            } catch {
                return
            }

            recorder.prepareToRecord()
            recorder.isMeteringEnabled = true
            recorder.record()
        }
        
        
    func setupScene() {
        // Setup world tracking and plane detection.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        arView.renderOptions = [.disableDepthOfField, .disableMotionBlur]
        arView.session.run(configuration)
        
        // Called every frame.
        scene.subscribe(to: SceneEvents.Update.self) { event in
            self.renderLoop()
        }.store(in: &subscriptions)
        
        // Process UI signals.
        viewModel.uiSignal.sink { [weak self] in
            self?.processUISignal($0)
        }.store(in: &subscriptions)
    
        // Respond to collision events.
        arView.scene.subscribe(to: CollisionEvents.Began.self) { event in

            print("💥 Collision with \(event.entityA.name) & \(event.entityB.name)")

        }.store(in: &subscriptions)

        // Setup tap gesture.
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        //
        // Uncomment to show collision debug.
        //arView.debugOptions = [.showPhysics]
    }

    // Process UI signals.
    func processUISignal(_ signal: ViewModel.UISignal) {
        switch signal {
        case .resetAnchor:
            resetPlaneAnchor()
        case .spin:
            print("in spin");
            spinWheels()
        }
    }

    // Handle taps.
    @objc func handleTap(_ sender: UITapGestureRecognizer? = nil) {
        guard let touchInView = sender?.location(in: self),
              let hitEntity = arView.entity(at: touchInView) else { return }

        print("👇 Did tap \(hitEntity.name)")
        
        // Respond to tap event.
        //hitEntity.scale *= [1.2, 1.2, 1.2]
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
          guard let touch = touches.first else { return }

        let deltaX = touch.location(in: self).x - touch.previousLocation(in: self).x
        pinwheels.orientation *= simd_quatf(angle: Float(deltaX) * -rotationGestureSpeed, axis: [0,0,1])
      }
    
    func spinWheels(){
        print("physics attempt");
        pinwheels.applyAngularImpulse([1,0,0], relativeTo: pinwheels)
        //pinwheels.applyLinearImpulse([4, 0, 0], relativeTo: pinwheels)
    }
   

    func setupEntities() {
        stick = try! Entity.loadModel(named: "Pinwheel8Stick.usdz")
        pinwheels = try! ModelEntity.loadModel(named: "Pinwheel8Blades.usdz")

        do {
            let resource = try AudioFileResource.load(named: "MerryGoRound.mp3", in: nil,
                                                      inputMode: .spatial, loadingStrategy: .preload,
                                                      shouldLoop: false)
            audioController = pinwheels.prepareAudio(resource)
        } catch {
            print("Error loading audio file")
        }
          
        planeAnchor = AnchorEntity(plane: [.horizontal])
        arView.scene.addAnchor(planeAnchor!)
        
        //Pauline's Variables:
        stick.transform = Transform.identity
        stick.scale = [0.0002878574312, 0.0002878574312, 0.0002878574312]
        stick.position.x = 0.015
        //stick.orientation *= simd_quatf(angle:.pi * 0.5, axis: [0,0,1])
        planeAnchor?.addChild(stick)

        pinwheels.transform = Transform.identity
        pinwheels.scale = [0.0002878574312, 0.0002878574312, 0.0002878574312]
        pinwheels.position.x = 0.015
        
        pinwheels.generateCollisionShapes(recursive: true)
        pinwheels.physicsBody = .init()
        pinwheels.physicsBody?.mode = .kinematic;
        pinwheels.physicsBody?.massProperties = .init()
        
        planeAnchor?.addChild(pinwheels);
        
        let test = ShapeResource.generateConvex(from: pinwheels.model!.mesh)
        pinwheels.components[CollisionComponent] = CollisionComponent(shapes: [test], mode: .default, filter: .default)
    }
    
 
    func resetPlaneAnchor() {
        planeAnchor?.removeFromParent()
        planeAnchor = nil
        
        planeAnchor = AnchorEntity(plane: [.horizontal])
        arView.scene.addAnchor(planeAnchor!)
        /*
        collisionBlockA.transform = Transform.identity
        collisionBlockA.position.x = -0.15
        planeAnchor?.addChild(collisionBlockA)

        collisionBlockB.transform = Transform.identity
        //collisionBlockB.position.x = 0.15
        planeAnchor?.addChild(collisionBlockB)
         */
       
    }

    func renderLoop() {
        
        var currentTime  = Date()
        var timeInterval = currentTime.timeIntervalSince(lastUpdateTime)
        
        recorder.updateMeters()
        let decibelPower = recorder.averagePower(forChannel: 0)
        //print("decibelPower: ", decibelPower)
        
        if(decibelPower > threshold && !hasBeenTriggered){
            audioController.play()
            hasBeenTriggered = true;
            lastUpdateTime = currentTime
        }
        
        if(audioController.isPlaying){
            pinwheels.orientation *= simd_quatf(angle: -.pi/6, axis: [0,0,1])
        }


       // Animate pinwheel if triggered
       if (timeInterval > 19 && hasBeenTriggered) {
           audioController.stop()
           print("stopping audio");
           lastUpdateTime = currentTime
           hasBeenTriggered = false
       }
    
    }
}

/*

class PinWheelBlades: Entity, HasPhysics, HasPhysicsBody, HasPhysicsMotion, HasModel, HasCollision {
    var model: Entity
    
    
    init(name: String){
        model = try! Entity.loadModel(named: "pinwheel5Blades.usdz")
        super.init()
        self.name = name
        // Set collision shape.
        self.collision = CollisionComponent(shapes: [.generateBox(size: [0.07,0.07,0.07])])
        self.addChild(model)
    }
    
    func isHit(){
        print("is hit!");
        self.applyLinearImpulse([4, 0, 0], relativeTo: self)

    }
    
    required init() {
        fatalError("init() has not been implemented")
    }
    
}
 */

