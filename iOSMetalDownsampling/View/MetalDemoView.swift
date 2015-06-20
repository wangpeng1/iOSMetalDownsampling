//
//  MetalDemoView.swift
//  iOSMetalDownsampling
//
//  Created by Bradley Griffith on 5/23/15.
//  Copyright (c) 2015 Bradley Griffith. All rights reserved.
//

import Foundation
import CoreMedia
import UIKit

struct GuassianSettings {
	var blurRadius: Int
	var width: Float
	var height: Float
}

class MetalDemoView: MetalView {
	
	var imagePlane: Node!
	
	var horizontalBlurPipeline: MTLRenderPipelineState!
	var verticallBlurPipeline: MTLRenderPipelineState!
	var upsamplePipeline: MTLRenderPipelineState!
	var compositePipeline: MTLRenderPipelineState!
	
	var horizontalBlurTexture: MTLTexture?
	var verticalBlurTexture: MTLTexture?
	var upsampleTexture: MTLTexture?
	var depthTexture: MTLTexture!
	
	var depthState: MTLDepthStencilState!
	
	var horizontalBlurBuffer: MTLRenderPassDescriptor?
	var verticalBlurBuffer: MTLRenderPassDescriptor?
	var upsampleBuffer: MTLRenderPassDescriptor?
	
	var baseZoomFactor: Float = 2
	var pinchZoomFactor: Float = 1
	
	var sharedGaussianBuffer: MTLBuffer?
	
	var defaultLibrary: MTLLibrary?
	
	
	var sampleLevel = 0
	var downsampleDataBuffer: MTLBuffer?
	
	var textureCache: TextureLevelCache?
	var textureUtility: TextureUtility?
	


	
	
	/* Lifecycle
	------------------------------------------*/
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		
		_setup()
	}
	
	required init(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		
		_setup()
	}
	
	private func _setup() {
		defaultLibrary = rendererDevice.newDefaultLibrary()!
		
		_createGeometries()
		_buildDepthBuffer()
		_createOutputTexturesForDownsample()
		_createPipelineStates()
		_createTextureCache()
	
		
		textureUtility = TextureUtility(texture: imagePlane.texture!, device: renderer.device)
		downsampleDataBuffer = renderer.device.newBufferWithBytes(&sampleLevel, length: sizeof(Int), options: MTLResourceOptions.OptionCPUCacheModeDefault)
		
		_setListeners()
	}
	
	
	/* Private Instance Methods
	------------------------------------------*/
	
	private func _createGeometries() {
		imagePlane = Plane(device: rendererDevice)
		imagePlane.samplerState = _generateSamplerStateForDevice(rendererDevice, mipped: true, minMagLinear: false)
		
		// NOTE: memory jump here.
		var texture = METLTexture(resourceName: "input", ext: "jpg")
		texture.format = MTLPixelFormat.BGRA8Unorm
		texture.finalize(renderer.device, flip: false)
		imagePlane.texture = texture.texture
		TextureUtility.generateMipmapsAcceleratedFromTexture(texture.texture, device: renderer.device, completionBlock: { (newTexture) -> Void in
			self.imagePlane.texture = newTexture
		})
		
		
		var sourceAspect: CGFloat = CGFloat(texture.texture.height) / CGFloat(texture.texture.width)
		imagePlane.scaleX = 1.0
		imagePlane.scaleY = Float(1.0 * sourceAspect)
	}
	
	private func _generateSamplerStateForDevice(device: MTLDevice, mipped: Bool, minMagLinear: Bool) -> MTLSamplerState {
		var pSamplerDescriptor:MTLSamplerDescriptor? = MTLSamplerDescriptor();
		
		if let sampler = pSamplerDescriptor
		{
			if mipped {
				sampler.mipFilter = MTLSamplerMipFilter.Linear
			}
			else {
				sampler.mipFilter = MTLSamplerMipFilter.NotMipmapped
			}
			
			if minMagLinear {
				sampler.minFilter = MTLSamplerMinMagFilter.Linear
				sampler.magFilter = MTLSamplerMinMagFilter.Linear
			}
			else {
				sampler.minFilter = MTLSamplerMinMagFilter.Nearest
				sampler.magFilter = MTLSamplerMinMagFilter.Nearest
			}
			
			sampler.maxAnisotropy         = 1
			sampler.sAddressMode          = MTLSamplerAddressMode.ClampToEdge
			sampler.tAddressMode          = MTLSamplerAddressMode.ClampToEdge
			sampler.rAddressMode          = MTLSamplerAddressMode.ClampToEdge
			sampler.normalizedCoordinates = true
			sampler.lodMinClamp           = 0
			sampler.lodMaxClamp           = FLT_MAX
		}
		else
		{
			// TODO: Make all error handling better.
			println(">> ERROR: Failed creating a sampler descriptor!")
		}
		
		return device.newSamplerStateWithDescriptor(pSamplerDescriptor!)
	}
	
	private func _buildDepthBuffer() {
		var drawableSize = metalLayer.drawableSize
		var depthTextureDesc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(MTLPixelFormat.Depth32Float, width:Int(drawableSize.width), height:Int(drawableSize.height), mipmapped:true)
		
		depthTexture = rendererDevice.newTextureWithDescriptor(depthTextureDesc)
	}
	
	private func _createOutputTexturesForDownsample() {
		let format = MTLPixelFormat.BGRA8Unorm
		let desc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(format, width: 720, height: 1280, mipmapped: false)
		
		
		horizontalBlurTexture = renderer.device.newTextureWithDescriptor(desc)
		
		horizontalBlurBuffer = MTLRenderPassDescriptor()
		horizontalBlurBuffer!.colorAttachments[0].texture = horizontalBlurTexture
		horizontalBlurBuffer!.colorAttachments[0].loadAction = MTLLoadAction.Load
		horizontalBlurBuffer!.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)
		horizontalBlurBuffer!.colorAttachments[0].storeAction = MTLStoreAction.Store
		
		
		verticalBlurTexture = renderer.device.newTextureWithDescriptor(desc)
		
		verticalBlurBuffer = MTLRenderPassDescriptor()
		verticalBlurBuffer!.colorAttachments[0].texture = verticalBlurTexture
		verticalBlurBuffer!.colorAttachments[0].loadAction = MTLLoadAction.Load
		verticalBlurBuffer!.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)
		verticalBlurBuffer!.colorAttachments[0].storeAction = MTLStoreAction.Store
		
		
		upsampleTexture = renderer.device.newTextureWithDescriptor(desc)
		
		upsampleBuffer = MTLRenderPassDescriptor()
		upsampleBuffer!.colorAttachments[0].texture = upsampleTexture
		upsampleBuffer!.colorAttachments[0].loadAction = MTLLoadAction.Load
		upsampleBuffer!.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)
		upsampleBuffer!.colorAttachments[0].storeAction = MTLStoreAction.Store
	}
	
	private func _createPipelineStates() {
		
		// Load all shaders needed for render pipeline
		let basicVert = defaultLibrary!.newFunctionWithName("basic_vertex")
		let basicFrag = defaultLibrary!.newFunctionWithName("basic_fragment")
		let horizontalBlurFrag = defaultLibrary!.newFunctionWithName("horizontal_box_blur_fragment")
		let verticalBlurFrag = defaultLibrary!.newFunctionWithName("vertical_box_blur_fragment")
		let compositeVert = defaultLibrary!.newFunctionWithName("composite_vertex")
		let compositeFrag = defaultLibrary!.newFunctionWithName("composite_fragment")
		
		var vertexDescriptor = MTLVertexDescriptor()
		vertexDescriptor.attributes[0].bufferIndex = 0
		vertexDescriptor.attributes[0].offset = 0
		vertexDescriptor.attributes[0].format = MTLVertexFormat.Float4
		vertexDescriptor.attributes[1].offset = 0
		vertexDescriptor.attributes[1].format = MTLVertexFormat.Float4
		vertexDescriptor.attributes[1].bufferIndex = 0
		vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunction.PerVertex
		vertexDescriptor.layouts[0].stepRate = 1
		vertexDescriptor.layouts[0].stride = sizeof(MMVertices)
		
		// Setup pipeline
		let desc = MTLRenderPipelineDescriptor()
		var pipelineError : NSError?
		
		desc.label = "Horizontal Blur"
		desc.vertexFunction = basicVert
		desc.fragmentFunction = horizontalBlurFrag
		desc.colorAttachments[0].pixelFormat = .BGRA8Unorm
		horizontalBlurPipeline = renderer.device.newRenderPipelineStateWithDescriptor(desc, error: &pipelineError)
		if !(horizontalBlurPipeline != nil) {
			println("Failed to create pipeline state, error \(pipelineError)")
		}
		
		desc.label = "Vertical Blur"
		desc.vertexFunction = basicVert
		desc.fragmentFunction = verticalBlurFrag
		desc.colorAttachments[0].pixelFormat = .BGRA8Unorm
		verticallBlurPipeline = renderer.device.newRenderPipelineStateWithDescriptor(desc, error: &pipelineError)
		if !(verticallBlurPipeline != nil) {
			println("Failed to create pipeline state, error \(pipelineError)")
		}
		
		desc.label = "Upsample"
		desc.vertexFunction = basicVert
		desc.fragmentFunction = basicFrag
		desc.colorAttachments[0].pixelFormat = .BGRA8Unorm
		upsamplePipeline = renderer.device.newRenderPipelineStateWithDescriptor(desc, error: &pipelineError)
		if !(upsamplePipeline != nil) {
			println("Failed to create pipeline state, error \(pipelineError)")
		}
		
		desc.label = "Composite"
		desc.vertexFunction = compositeVert
		desc.vertexDescriptor = vertexDescriptor
		desc.fragmentFunction = compositeFrag
		desc.colorAttachments[0].pixelFormat = .BGRA8Unorm
		desc.depthAttachmentPixelFormat = MTLPixelFormat.Depth32Float;
		compositePipeline = renderer.device.newRenderPipelineStateWithDescriptor(desc, error: &pipelineError)
		if !(compositePipeline != nil) {
			println("Failed to create pipeline state, error \(pipelineError)")
		}
		
		var depthDesc: MTLDepthStencilDescriptor = MTLDepthStencilDescriptor()
		depthDesc.depthCompareFunction = MTLCompareFunction.Less;
		depthDesc.depthWriteEnabled = true;
		depthState = rendererDevice.newDepthStencilStateWithDescriptor(depthDesc)
	}
	
	private func _createTextureCache() {
		textureCache = TextureLevelCache(texture: imagePlane.texture!, device: renderer.device)
	}
	
	private func _setListeners() {
		let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: "pinchGesture:")
		self.addGestureRecognizer(pinchRecognizer)
	}
	
	private func _currentFrameBufferForDrawable(drawable: CAMetalDrawable) -> MTLRenderPassDescriptor {
		var currentFrameBuffer = MTLRenderPassDescriptor()
		
		currentFrameBuffer.colorAttachments[0].texture = drawable.texture
		currentFrameBuffer.colorAttachments[0].loadAction = MTLLoadAction.Clear
		currentFrameBuffer.colorAttachments[0].storeAction = MTLStoreAction.Store
		currentFrameBuffer.colorAttachments[0].clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1)
		
		currentFrameBuffer.depthAttachment.texture = depthTexture;
		currentFrameBuffer.depthAttachment.loadAction = MTLLoadAction.Clear;
		currentFrameBuffer.depthAttachment.storeAction = MTLStoreAction.DontCare;
		currentFrameBuffer.depthAttachment.clearDepth = 1;
		
		return currentFrameBuffer
	}
	
	private func _encodeHorizontalBoxBlurRenderPass(commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable, uniformsBuffer: MTLBuffer) {
		
		var encoder = commandBuffer.renderCommandEncoderWithDescriptor(horizontalBlurBuffer!)!
		
		encoder.pushDebugGroup("Horizontal blur render")
		encoder.setCullMode(MTLCullMode.None)
		encoder.setRenderPipelineState(horizontalBlurPipeline!)
		encoder.setFragmentTexture(imagePlane.texture, atIndex: 0)
		encoder.setFragmentSamplerState(imagePlane.samplerState!, atIndex: 0)
		encoder.setVertexBuffer(imagePlane.vertexBuffer, offset: 0, atIndex: 0)
		encoder.setVertexBuffer(uniformsBuffer, offset: 0, atIndex: 1)
		
		encoder.setFragmentBuffer(downsampleDataBuffer, offset: 0, atIndex: 0)
		
		encoder.drawIndexedPrimitives(
			.Triangle,
			indexCount: imagePlane.indexBuffer.length / sizeof(MMIndexType),
			indexType: MTLIndexType.UInt16,
			indexBuffer: imagePlane.indexBuffer,
			indexBufferOffset: 0
		)
		
		encoder.popDebugGroup()
		encoder.endEncoding()
	}
	
	private func _encodeVerticalBoxBlurRenderPass(commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable, uniformsBuffer: MTLBuffer) {
		
		verticalBlurTexture = textureCache?.textureAtLevel(sampleLevel)
		verticalBlurBuffer?.colorAttachments[0].texture = textureCache?.textureAtLevel(sampleLevel)
		
		var encoder = commandBuffer.renderCommandEncoderWithDescriptor(verticalBlurBuffer!)!
		
		encoder.pushDebugGroup("Vertical blur render")
		encoder.setCullMode(MTLCullMode.None)
		encoder.setRenderPipelineState(verticallBlurPipeline!)
		encoder.setFragmentTexture(horizontalBlurTexture, atIndex: 0)
		encoder.setFragmentSamplerState(imagePlane.samplerState!, atIndex: 0)
		encoder.setVertexBuffer(imagePlane.vertexBuffer, offset: 0, atIndex: 0)
		encoder.setVertexBuffer(uniformsBuffer, offset: 0, atIndex: 1)
		
		encoder.setFragmentBuffer(downsampleDataBuffer, offset: 0, atIndex: 0)
		
		encoder.drawIndexedPrimitives(
			.Triangle,
			indexCount: imagePlane.indexBuffer.length / sizeof(MMIndexType),
			indexType: MTLIndexType.UInt16,
			indexBuffer: imagePlane.indexBuffer,
			indexBufferOffset: 0
		)
		
		encoder.popDebugGroup()
		encoder.endEncoding()
	}
	
	private func _encodeUpsampleRenderPass(commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable, uniformsBuffer: MTLBuffer) {
		
		var encoder = commandBuffer.renderCommandEncoderWithDescriptor(upsampleBuffer!)!
		
		encoder.pushDebugGroup("Upsample render")
		encoder.setCullMode(MTLCullMode.None)
		encoder.setRenderPipelineState(upsamplePipeline!)
		encoder.setFragmentTexture(verticalBlurTexture, atIndex: 0)
		encoder.setFragmentSamplerState(imagePlane.samplerState!, atIndex: 0)
		encoder.setVertexBuffer(imagePlane.vertexBuffer, offset: 0, atIndex: 0)
		encoder.setVertexBuffer(uniformsBuffer, offset: 0, atIndex: 1)
		encoder.drawIndexedPrimitives(
			.Triangle,
			indexCount: imagePlane.indexBuffer.length / sizeof(MMIndexType),
			indexType: MTLIndexType.UInt16,
			indexBuffer: imagePlane.indexBuffer,
			indexBufferOffset: 0
		)
		
		encoder.popDebugGroup()
		encoder.endEncoding()
		
		textureUtility?.texture = self.upsampleBuffer?.colorAttachments[0].texture
		textureUtility?.generateMipmaps(commandBuffer, completionBlock: { (newTexture) -> Void in
			self.upsampleTexture = newTexture
		})
	}
	
	private func _encodeCompositeRenderPass(commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable, uniformsBuffer: MTLBuffer) {
		
		var encoder = commandBuffer.renderCommandEncoderWithDescriptor(_currentFrameBufferForDrawable(drawable))!
		
		encoder.pushDebugGroup("imagePlane render")
		encoder.setFrontFacingWinding(MTLWinding.CounterClockwise)
		encoder.setCullMode(MTLCullMode.None)
		encoder.setRenderPipelineState(compositePipeline)
		encoder.setDepthStencilState(depthState)
		encoder.setFragmentTexture(upsampleTexture, atIndex: 0)
		encoder.setFragmentSamplerState(imagePlane.samplerState!, atIndex: 0)
		//encoder.setTriangleFillMode(MTLTriangleFillMode.Lines)
		encoder.setVertexBuffer(imagePlane.vertexBuffer, offset: 0, atIndex: 0)
		encoder.setVertexBuffer(uniformsBuffer, offset: 0, atIndex: 1)
		encoder.drawIndexedPrimitives(
			.Triangle,
			indexCount: imagePlane.indexBuffer.length / sizeof(MMIndexType),
			indexType: MTLIndexType.UInt16,
			indexBuffer: imagePlane.indexBuffer,
			indexBufferOffset: 0
		)
		
		encoder.popDebugGroup()
		encoder.endEncoding()
	}
	
	
	/* Public Instance Methods
	------------------------------------------*/
	
	func pinchGesture(gesture: UIPinchGestureRecognizer) {
		var scale: Float = Float(1.0 / gesture.scale)
		
		switch gesture.state
		{
		case UIGestureRecognizerState.Changed:
			pinchZoomFactor = scale
			break
		case UIGestureRecognizerState.Ended:
			baseZoomFactor = baseZoomFactor * pinchZoomFactor
			pinchZoomFactor = 1
		default:
			break
		}
		
		var constrainedZoom = fmaxf(1.0, fminf(100.0, baseZoomFactor * pinchZoomFactor))
		pinchZoomFactor = constrainedZoom / baseZoomFactor
	}
	
	override func gameloop(displayLink: CADisplayLink) {
		renderer.cameraZ = baseZoomFactor * pinchZoomFactor;
		
		super.gameloop(displayLink)
	}
	
	override func configureComputeEncoders(commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable) {
	}
	
	override func configureRenderEncoders(commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable) {
		dispatch_semaphore_wait(imagePlane.avaliableResourcesSemaphore, DISPATCH_TIME_FOREVER)
		
		var drawableSize = metalLayer.drawableSize
		if (depthTexture.width != Int(drawableSize.width) || depthTexture.height != Int(drawableSize.height)) {
			_buildDepthBuffer()
		}
		
		let uniformsBuffer = imagePlane.adjustUniformsForSceneUsingWorldMatrix(renderer.worldMatrix, projectionMatrix:renderer.projectionMatrix)
		
		self._encodeHorizontalBoxBlurRenderPass(commandBuffer, drawable: drawable, uniformsBuffer: uniformsBuffer)
		self._encodeVerticalBoxBlurRenderPass(commandBuffer, drawable: drawable, uniformsBuffer: uniformsBuffer)
		self._encodeUpsampleRenderPass(commandBuffer, drawable: drawable, uniformsBuffer: uniformsBuffer)
		self._encodeCompositeRenderPass(commandBuffer, drawable: drawable, uniformsBuffer: uniformsBuffer)
		
		commandBuffer.addCompletedHandler { (commandBuffer) -> Void in
			var temp = dispatch_semaphore_signal(self.imagePlane.avaliableResourcesSemaphore)
		}
	}
	
	func setApproximateDetailLevel(approxLevel: Float) {
		let newLevel = textureCache!.levelForNormalizedScale(approxLevel)
		
		if (newLevel != sampleLevel) {
			println("new level: \(newLevel)")
		}
		sampleLevel = newLevel
		memcpy(downsampleDataBuffer!.contents(), &sampleLevel, UInt(sizeof(Int)))
	}
}