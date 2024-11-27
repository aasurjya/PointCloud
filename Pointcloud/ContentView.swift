//
//  ContentView.swift
//  Pointcloud
//
//  Created by Aasurjya Handique on 24/11/24.
//

import SwiftUI
import RealityKit

struct ContentView : View {

    var body: some View {
        RealityView { content in

            // Create a cube model
            let cubeModel = Entity()
            let cubeMesh = MeshResource.generateBox(size: 0.1, cornerRadius: 0.005)
            let cubeMaterial = SimpleMaterial(color: .gray, roughness: 0.01, isMetallic: true)
            cubeModel.components.set(ModelComponent(mesh: cubeMesh, materials: [cubeMaterial]))
            cubeModel.position = [0, 0.05, 0]


            

            //Create a cyclinder model
            let cyclinderModel = Entity()
            let cyclinderMesh = MeshResource.generateCylinder(height: 0.1, radius: 0.04)
            let cyclinderMaterials = SimpleMaterial(color: .brown, isMetallic: true)
            cyclinderModel.components.set(ModelComponent(mesh: cyclinderMesh, materials: [cyclinderMaterials]))
            cyclinderModel.position = [0.15, 0.05, 0]

            
            // Create horizontal plane anchor for the content
            let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: SIMD2<Float>(0.2, 0.2)))
            anchor.addChild(cubeModel)
            anchor.addChild(cyclinderModel)

            // Add the horizontal plane anchor to the scene
            content.add(anchor)

            content.camera = .spatialTracking

        }
        .edgesIgnoringSafeArea(.all)
    }

}

#Preview {
    ContentView()
}
