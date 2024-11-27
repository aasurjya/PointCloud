import SwiftUI
import RealityKit
import ARKit
import SceneKit
import Combine

// ObservableObject to hold and share the ARView instance
class ARViewModel: ObservableObject {
    @Published var arView: ARView?
}

struct ContentView: View {
    @StateObject var arViewModel = ARViewModel()
    @State private var isSaving = false // State to manage save status

    var body: some View {
        ZStack {
            // ARView Container
            ARViewContainer()
                .edgesIgnoringSafeArea(.all)
                .environmentObject(arViewModel) // Pass the model to the environment

            // Save Button
            VStack {
                Spacer()
                Button(action: saveMesh) {
                    Text(isSaving ? "Saving..." : "Save Mesh")
                        .padding()
                        .background(isSaving ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
                .disabled(isSaving) // Disable button while saving
            }
        }
    }

    // Save Mesh Function
    func saveMesh() {
        print("Save Mesh button pressed.")
        isSaving = true

        // Access the ARView from the model
        if let arView = arViewModel.arView {
            print("ARView found.")
            if let coordinator = arView.session.delegate as? ARSessionDelegateCoordinator {
                print("Coordinator found. Starting mesh export...")
                // Perform the export on a background thread
                DispatchQueue.global(qos: .userInitiated).async {
                    coordinator.exportMesh()
                    // Update UI on the main thread
                    DispatchQueue.main.async {
                        self.isSaving = false
                    }
                }
            } else {
                print("Coordinator not found.")
                isSaving = false
            }
        } else {
            print("ARView not found.")
            isSaving = false
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject var arViewModel: ARViewModel

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

        // Set the arView in the model
        arViewModel.arView = arView

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
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        print("Added anchors: \(anchors.count)")
        updateMeshAnchors(with: anchors)
    }

    // Capture updated anchors
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        print("Updated anchors: \(anchors.count)")
        updateMeshAnchors(with: anchors)
    }

    private func updateMeshAnchors(with anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                // Avoid adding duplicate anchors
                if !meshAnchors.contains(where: { $0.identifier == meshAnchor.identifier }) {
                    print("Mesh anchor added with identifier: \(meshAnchor.identifier)")
                    meshAnchors.append(meshAnchor)
                }
            }
        }
    }

    // Export the mesh
    func exportMesh() {
        print("Exporting mesh...")
        guard !meshAnchors.isEmpty else {
            print("No mesh data available to export.")
            return
        }

        // Create a SceneKit scene to store the mesh
        let scene = SCNScene()
        print("Scene created.")

        for (index, meshAnchor) in meshAnchors.enumerated() {
            print("Processing mesh anchor \(index + 1)/\(meshAnchors.count)")
            // Create the mesh node
            let meshNode = createMeshNode(from: meshAnchor.geometry, withTransform: meshAnchor.transform)
            scene.rootNode.addChildNode(meshNode)
        }

        // Save the scene to the Documents directory
        let fileManager = FileManager.default
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentsURL.appendingPathComponent("RoomMesh.obj")

            do {
                print("Saving scene to \(fileURL.path)")
                try scene.write(to: fileURL, options: nil, delegate: nil, progressHandler: { (totalProgress, error, stop) in
                    print("Export progress: \(totalProgress)")
                })
                print("Mesh successfully saved at: \(fileURL)")
            } catch {
                print("Failed to save mesh: \(error.localizedDescription)")
            }
        }
    }

    // Helper to create SCNGeometry from ARMeshGeometry
    private func createMeshNode(from meshGeometry: ARMeshGeometry, withTransform transform: simd_float4x4) -> SCNNode {
        print("Creating mesh node...")
        // Extract vertices
        let vertexCount = meshGeometry.vertices.count
        print("Vertex count: \(vertexCount)")
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
        print("Face count: \(faceCount)")
        let indexBuffer = meshGeometry.faces.buffer
        let indexCountPerPrimitive = meshGeometry.faces.indexCountPerPrimitive
        let indexStride = indexCountPerPrimitive * MemoryLayout<UInt32>.size
        let indicesPointer = indexBuffer.contents()

        var indices = [UInt32]()
        for i in 0..<faceCount {
            let indexOffset = i * indexStride
            let indexPointer = indicesPointer.advanced(by: indexOffset)
            for j in 0..<indexCountPerPrimitive {
                let idx = indexPointer.load(fromByteOffset: j * MemoryLayout<UInt32>.size, as: UInt32.self)
                indices.append(idx)
            }
        }

        // Create SceneKit geometry from vertices and indices
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let geometryElement = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        let geometry = SCNGeometry(sources: [vertexSource], elements: [geometryElement])
        geometry.firstMaterial?.diffuse.contents = UIColor.gray

        let node = SCNNode(geometry: geometry)
        print("Mesh node created.")
        return node
    }
}
