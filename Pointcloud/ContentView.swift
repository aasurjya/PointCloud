import SwiftUI
import RealityKit
import ARKit
import SceneKit

struct ContentView: View {
    @State private var isSaving = false // State to manage save status

    var body: some View {
        ZStack {
            // ARView Container
            ARViewContainer()
                .edgesIgnoringSafeArea(.all)

            // Save Button
            VStack {
                Spacer()
                Button(action: saveMesh) {
                    Text(isSaving ? "Saving..." : "Save Mesh")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
                .disabled(isSaving) // Disable button while saving
            }
        }
    }

    // Save Mesh Function
    // Save Mesh Function
    func saveMesh() {
        print("Save Mesh button pressed.")
        isSaving = true

        // Trigger exportMesh on the coordinator
        if let arView = UIApplication.shared.windows.first?.rootViewController?.view.subviews.first(where: { $0 is ARView }) as? ARView {
            print("ARView found.")
            if let coordinator = arView.session.delegate as? ARSessionDelegateCoordinator {
                print("Coordinator found. Starting mesh export...")
                coordinator.exportMesh()
            } else {
                print("Coordinator not found.")
            }
        } else {
            print("ARView not found.")
        }

        isSaving = false
    }

}

struct ARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Enable Scene Reconstruction
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .meshWithClassification
        arView.session.run(configuration)

        // Enable Debug Options (to visualize mesh and features)
        arView.debugOptions = [.showSceneUnderstanding, .showFeaturePoints]

        // Assign Delegate
        arView.session.delegate = context.coordinator

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> ARSessionDelegateCoordinator {
        return ARSessionDelegateCoordinator()
    }
}

class ARSessionDelegateCoordinator: NSObject, ARSessionDelegate {
    var meshAnchors: [ARMeshAnchor] = []

    // Capture added anchors
    // Capture added anchors
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        print("Added anchors: \(anchors.count)")
        updateMeshAnchors(with: anchors)
    }

    // Capture updated anchors
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        updateMeshAnchors(with: anchors)
    }

    private func updateMeshAnchors(with anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                meshAnchors.append(meshAnchor)
            }
        }
    }

    // Export the mesh
    func exportMesh() {
        guard !meshAnchors.isEmpty else {
            print("No mesh data available to export.")
            return
        }

        // Create a SceneKit scene to store the mesh
        let scene = SCNScene()
        for meshAnchor in meshAnchors {
            // Create the mesh node
            let meshNode = createMeshNode(from: meshAnchor.geometry, withTransform: meshAnchor.transform)
            scene.rootNode.addChildNode(meshNode)
        }

        // Save the scene to the Documents directory
        let fileManager = FileManager.default
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentsURL.appendingPathComponent("RoomMesh.obj")

            do {
                try scene.write(to: fileURL, options: nil, delegate: nil, progressHandler: nil)
                print("Mesh successfully saved at: \(fileURL)")
            } catch {
                print("Failed to save mesh: \(error.localizedDescription)")
            }
        }
    }

    // Helper to create SCNGeometry from ARMeshGeometry
    private func createMeshNode(from meshGeometry: ARMeshGeometry, withTransform transform: simd_float4x4) -> SCNNode {
        // Extract vertices
        let vertexCount = meshGeometry.vertices.count
        let vertexStride = meshGeometry.vertices.stride
        let vertexBuffer = meshGeometry.vertices.buffer
        let vertexOffset = meshGeometry.vertices.offset
        let verticesPointer = vertexBuffer.contents().advanced(by: vertexOffset)

        var vertices = [SCNVector3]()
        for i in 0..<vertexCount {
            let vertexPointer = verticesPointer.advanced(by: i * vertexStride)
            let vertex = vertexPointer.load(as: SIMD3<Float>.self)

            // Apply the mesh anchor's transform to get world coordinates
            let position = simd_float4(vertex.x, vertex.y, vertex.z, 1.0)
            let worldPosition = simd_mul(transform, position)
            vertices.append(SCNVector3(worldPosition.x, worldPosition.y, worldPosition.z))
        }

        // Extract face indices
        let faceCount = meshGeometry.faces.count
        let indexBuffer = meshGeometry.faces.buffer
        let indexStride = meshGeometry.faces.indexCountPerPrimitive * MemoryLayout<UInt32>.size
        let indicesPointer = indexBuffer.contents()

        var indices = [UInt32]()
        for i in 0..<faceCount {
            let indexOffset = i * indexStride
            let indexPointer = indicesPointer.advanced(by: indexOffset)
            let index0 = indexPointer.load(as: UInt32.self)
            let index1 = indexPointer.advanced(by: 4).load(as: UInt32.self)
            let index2 = indexPointer.advanced(by: 8).load(as: UInt32.self)

            indices.append(index0)
            indices.append(index1)
            indices.append(index2)
        }

        // Create SceneKit geometry from vertices and indices
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let geometryElement = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        let geometry = SCNGeometry(sources: [vertexSource], elements: [geometryElement])
        geometry.firstMaterial?.diffuse.contents = UIColor.gray

        let node = SCNNode(geometry: geometry)
        return node
    }
}
