//
//  PostListNodeViewController.swift
//  MVVMApp
//
//  Created by George Kaimakas on 28/10/2017.
//  Copyright © 2017 George Kaimakas. All rights reserved.
//
import AsyncDisplayKit
import ASDKFluentExtensions
import ChameleonFramework
import Foundation
import MVVMAppModels
import MVVMAppViewModels
import MVVMAppViews
import ReactiveCocoa
import ReactiveSwift
import Result
import Swinject
import UIKit

class PostListNodeController: ASViewController<ASTableNode> {

	let viewModel: PostListViewModel!
    let fetchListDisposable = SerialDisposable()
    let fetchCommentsDisposable = SerialDisposable()
    let loadingDisposable = SerialDisposable()

	var loadingIndicator: UIActivityIndicatorView!
	var loadingBarButtonItem: UIBarButtonItem!
	var context: ASBatchContext!

    var impactGenerator = UIImpactFeedbackGenerator()
    var notificationGenerator = UINotificationFeedbackGenerator()

	init() {
		viewModel = UIApplication.inject(PostListViewModel.self)
		super.init(node: ASTableNode())
	}

	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		navigationItem.title = "MVVMApp"
		loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
		loadingIndicator.color = UIColor.flatMintDark
		loadingIndicator.hidesWhenStopped = true
		loadingBarButtonItem = UIBarButtonItem(customView: loadingIndicator)
		self.navigationItem.setRightBarButton(loadingBarButtonItem, animated: true)

		loadingIndicator.reactive.isAnimating <~ viewModel.fetchPosts
			.isExecuting

		node.autoresizingMask = [.flexibleHeight, .flexibleWidth]
		node.dataSource = self
		node.delegate = self
		node.isUserInteractionEnabled = true
		node.allowsSelection = true
		node.clipsToBounds = true
		node.view.separatorStyle = .none
		node.leadingScreensForBatching = 3

		self.reactive.updatePostList <~ viewModel
			.fetchPosts
			.values

		self.view.backgroundColor = UIColor.flatWhite
		self.node.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 12, right: 0)

	}

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        impactGenerator.prepare()
    }

	func insertSections(newCount: Int) {
		let indexRange = (viewModel.posts.value.count - newCount..<viewModel.posts.value.count)
		let set = IndexSet(integersIn: indexRange)
		node.insertSections(set, with: .fade)
	}

	func insertRows(in section: Int, newCount: Int) {
		let start = viewModel.posts.value[section].comments.value.count - newCount + 1
		let end = viewModel.posts.value[section].comments.value.count+1
		let indexRange =  start ..< end
		let indexPaths = indexRange.map { IndexPath(row: $0, section: section) }
		node.insertRows(at: indexPaths, with: .fade)
	}
}

extension PostListNodeController: ASTableDataSource {

	func numberOfSections(in tableNode: ASTableNode) -> Int {
		return viewModel.posts.value.count
	}

	func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
		return 1 + viewModel.posts.value[section].comments.value.count
	}


	func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {

		if indexPath.row == 0 {
			let post = viewModel.posts.value[indexPath.section]
			return {
				let node = PostNode(viewModel: post)
				node.cornerRadius = 12
				let wrapper = WrapperCellNode<PostNode>(wrapped: node,
				                                        inset: UIEdgeInsets(top: 12,
				                                                            left: 16,
				                                                            bottom: 4,
				                                                            right: 16))
				wrapper.cornerRoundingType = .precomposited
				return wrapper
			}
		}

		if indexPath.row != 0 {
			let comment = viewModel.posts.value[indexPath.section].comments.value[indexPath.row-1]
			return {
				let node = CommentNode(viewModel: comment)
				return WrapperCellNode<CommentNode>(wrapped: node,
				                                    inset: UIEdgeInsets(top: 2,
				                                                        left: 32,
				                                                        bottom: 4,
				                                                        right: 32))
			}
		}

		return {
			return ASCellNode()
		}
	}
}

extension PostListNodeController: ASTableDelegate {
	func shouldBatchFetch(for tableNode: ASTableNode) -> Bool {
		return viewModel.fetchPosts.isExecuting.negate().value || viewModel.posts.value.count < 100
	}


	func tableNode(_ tableNode: ASTableNode, willBeginBatchFetchWith context: ASBatchContext) {
		context.reactive.completBatchFetching <~ viewModel.fetchPosts
			.isExecuting
			.producer
			.filter { $0 == false }
			.negate()

			viewModel
				.fetchPosts
				.apply()
				.start()
	}

	func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {

		if indexPath.row == 0,
			case let post = viewModel.posts.value[indexPath.section],
			post.comments.value.count == 0,
			post.fetchComments.isExecuting.value == false,
			post.fetchComments.isEnabled.value == true {

			loadingDisposable.inner = loadingIndicator.reactive.isAnimating <~ post
				.fetchComments
				.isExecuting

			fetchListDisposable.inner = reactive.updateCommentList(section: indexPath.section) <~ post
				.fetchComments
				.values

			post.fetchComments
				.apply()
				.start()

            post.fetchComments
                .events
                .observe({ event in
                    switch event {
                    case .value: self.notificationGenerator.notificationOccurred(.success)
                    case .failed: self.notificationGenerator.notificationOccurred(.error)
                    default: break
                    }
                })

            impactGenerator.impactOccurred()
            impactGenerator.prepare()
		}
	}
}

extension Reactive where Base == PostListNodeController {
	var updatePostList: BindingTarget<[PostViewModel]> {
		return makeBindingTarget { $0.insertSections(newCount: $1.count) }
	}

	func updateCommentList(section: Int) -> BindingTarget<[CommentViewModel]> {
		return makeBindingTarget { $0.insertRows(in: section, newCount: $1.count) }
	}
}

extension Reactive where Base == ASBatchContext {
	var completBatchFetching: BindingTarget<Bool> {
		return makeBindingTarget { $0.completeBatchFetching($1) }
	}
}
