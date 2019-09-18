import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet var sceneView: ARSCNView!
    let configuration = ARWorldTrackingConfiguration()
    var selectedNode: SCNNode?
    
    enum ObjectPlacementMode {
        case freeform, plane, image
    }
    
    var lastObjectPlacedPoint: CGPoint?
    let touchDistanceThreshold: CGFloat = 40.0
    var showPlaneOverlay = false {
        didSet {
            for node in planeNodes {
                node.isHidden = !showPlaneOverlay
            }
        }
    }
    var objectMode: ObjectPlacementMode = .freeform {
        didSet {
            reloadConfiguration()
        }
    }
    var placedNodes = [SCNNode]()
    var planeNodes = [SCNNode]()
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let imageAnchor = anchor as? ARImageAnchor {
            nodeAdded(node, for: imageAnchor)
        } else if let planeAnchor = anchor as? ARPlaneAnchor {
            nodeAdded(node, for: planeAnchor)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor, let planeNode = node.childNodes.first, let plane = planeNode.geometry as? SCNPlane else { return }
        planeNode.position = SCNVector3(planeAnchor.extent.x, 0, planeAnchor.extent.z)
        plane.width = CGFloat(planeAnchor.extent.x)
        plane.height = CGFloat(planeAnchor.extent.z)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadConfiguration()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        guard let node = selectedNode, let touch = touches.first else { return }
        
        switch objectMode {
        case .freeform:
            addNodeInFront(node)
        case .plane:
            let touchPoint = touch.location(in: sceneView)
            addNode(node, toPlaneUsingPoint: touchPoint)
        case .image:
            break
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        guard objectMode == .plane, let node = selectedNode, let touch = touches.first, let lastTouchPoint = lastObjectPlacedPoint else { return }
        
        let newTouchPoint = touch.location(in: sceneView)
        let distance = sqrt(pow(newTouchPoint.x - lastTouchPoint.x, 2) + pow(newTouchPoint.y - lastTouchPoint.y, 2))
        if distance > touchDistanceThreshold {
            addNode(node, toPlaneUsingPoint: newTouchPoint)
        }
        
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        lastObjectPlacedPoint = nil
    }
    
    func addNodeInFront(_ node: SCNNode) {
        guard let currentFrame = sceneView.session.currentFrame else { return }
        
        var translation = matrix_identity_float4x4
        translation.columns.3.z = -0.2
        node.simdTransform = matrix_multiply(currentFrame.camera.transform, translation)
        
        addNodeToSceneRoot(node)
    }
    
    func nodeAdded(_ node: SCNNode, for anchor: ARPlaneAnchor) {
        let planeNode = createHonrizontalPlane(planeAnchor: anchor)
        planeNode.isHidden = !showPlaneOverlay
        node.addChildNode(planeNode)
        planeNodes.append(planeNode)
    }
    
    func nodeAdded(_ node: SCNNode, for anchor: ARImageAnchor) {
        guard let selectedNode = selectedNode else { return }
        addNode(selectedNode, toParent: node)
    }
    
    func addNodeToSceneRoot(_ node: SCNNode) {
        let cloneNode = node.clone()
        sceneView.scene.rootNode.addChildNode(cloneNode)
        placedNodes.append(cloneNode)
    }
    
    func addNode(_ node: SCNNode, toParent parent: SCNNode) {
        let cloneNode = node.clone()
        parent.addChildNode(cloneNode)
        placedNodes.append(cloneNode)
    }
    
    func addNode(_ node: SCNNode, toPlaneUsingPoint point: CGPoint) {
        let results = sceneView.hitTest(point, types: [.existingPlaneUsingExtent])
        
        if let result = results.first {
            let transform = result.worldTransform
            node.position = SCNVector3(x: transform.columns.3.x, y: transform.columns.3.y, z: transform.columns.3.z)
            addNodeToSceneRoot(node)
            lastObjectPlacedPoint = point
        }
    }
    
    func reloadConfiguration(removeAnchors: Bool = false) {
        configuration.detectionImages = objectMode == .image ? ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) : nil
        configuration.planeDetection = [.horizontal, .vertical]
        let options: ARSession.RunOptions
        
        if removeAnchors {
            options = .removeExistingAnchors
            for node in planeNodes {
                node.removeFromParentNode()
            }
            planeNodes.removeAll()
            for node in placedNodes {
                node.removeFromParentNode()
            }
            placedNodes.removeAll()
        } else {
            options = []
        }
        
        sceneView.session.run(configuration, options: options)
    }
    
    func createHonrizontalPlane(planeAnchor: ARPlaneAnchor) -> SCNNode {
        let node = SCNNode()
        node.geometry = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
        node.eulerAngles.x = -Float.pi / 2
        node.opacity = 0.25
        
        return node
    }

    @IBAction func changeObjectMode(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            objectMode = .freeform
        case 1:
            objectMode = .plane
        case 2:
            objectMode = .image
        default:
            break
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showOptions" {
            let optionsViewController = segue.destination as! OptionsContainerViewController
            optionsViewController.delegate = self
        }
    }
}

extension ViewController: OptionsViewControllerDelegate {
    
    func objectSelected(node: SCNNode) {
        dismiss(animated: true, completion: nil)
        selectedNode = node
    }
    
    func togglePlaneVisualization() {
        showPlaneOverlay = !showPlaneOverlay
        dismiss(animated: true, completion: nil)
    }
    
    func undoLastObject() {
        if let lastNode = placedNodes.last {
            lastNode.removeFromParentNode()
            placedNodes.removeLast()
        }
    }
    
    func resetScene() {
        reloadConfiguration(removeAnchors: true)
        dismiss(animated: true, completion: nil)
    }
}
