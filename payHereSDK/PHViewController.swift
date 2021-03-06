//
//  PHViewController.swift
//  sdk
//
//  Created by Kamal Sampath Upasena on 3/5/18.
//  Copyright © 2018 PayHere. All rights reserved.
//

import UIKit
import Alamofire
import AlamofireObjectMapper

public protocol PHViewControllerDelegate{
    func onResponseReceived(response : PHResponse<Any>?)
}
public class PHViewController: UIViewController {
    
    var delegate : PHViewControllerDelegate?
    
    var initRequest : InitRequest?
    var orderKey: String?
    var lastResponse : StatusResponse?
    var dataLoading : Bool = false;
    var baseUrl : String?
    var isSandBoxEnabled : Bool = false
    
    var webView : UIWebView?
    var progressBar : UIActivityIndicatorView?
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        if(initRequest == nil){
            let response : PHResponse<Any> =  PHResponse(status: PHResponse<Any>.STATUS_ERROR_DATA, message: PHConstants.INTENT_EXTRA_DATA + " not found");
            
            
            self.dismiss(animated: true, completion: {
                self.delegate?.onResponseReceived(response: response)
            })
        }
        
        webView  = UIWebView(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width * 0.9, height: self.view.frame.height * 0.9))
        webView?.delegate = self
        
        webView?.center = view.convert(view.center, from: view.superview)
        webView?.scrollView.bounces = false
        webView?.scrollView.showsVerticalScrollIndicator = false
        webView?.scrollView.showsHorizontalScrollIndicator = false
        
        progressBar = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
        progressBar?.isHidden = true
        progressBar?.center = view.convert(view.center, from: view.superview)
        progressBar?.color = UIColor.blue
        
        
        
        self.view.addSubview(webView!)
        self.view.addSubview(progressBar!)
        
        self.view.backgroundColor = UIColor.clear
        
        if(isSandBoxEnabled){
            PHConfigs.setBaseUrl(url: PHConfigs.SANDBOX_URL)
        }else{
            PHConfigs.setBaseUrl(url: PHConfigs.LIVE_URL)
        }
        
        
        
        startProcess()
    }
    
    override public func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    private func startProcess(){
        
        let validate = self.Validate()
        
        if(validate == nil){
            checkNetworkAvailability();
        }
        
    }
    
    private func webViewPost(webView : UIWebView,baseUrl : String,url : String,postData : [String: String?]){
        var sb : String?
        
        sb = "<html><head></head>"
        sb = sb! + "<body onload='form1.submit()'>"
        sb = sb! + String(format:"<form id='form1' action='%@' method='%@'>", url, "post")
        for item in postData{
            if(item.value != nil){
                sb = sb! + String(format:"<input name='%@' type='hidden' value='%@' />",item.key, item.value!)
            }
        }
        
        sb = sb! + "</form></body></html>"
        
        webView.loadHTMLString(sb!, baseURL: nil)
        
    }
    
    private func checkNetworkAvailability(){
        
        var connection : Bool = false
        
        let net = NetworkReachabilityManager()
        
        net?.startListening()
        
        net?.listener = { status in
            if(net?.isReachable ?? false){
                
                switch status{
                case .reachable(.ethernetOrWiFi):
                    connection = true
                    
                case .reachable(.wwan):
                    connection = true
                    
                case .notReachable:
                    connection = false
                    
                case .unknown :
                    connection = false
                    
                }
                
                if (!connection) {
                    
                    self.dismiss(animated: true, completion: {
                        self.delegate?.onResponseReceived(response: PHResponse(status: PHResponse<Any>.STATUS_ERROR_NETWORK, message: "Unable to connect to the internet"))
                    })
                }else{
                    let params = ParamHandler.createParams(req: self.initRequest!)
                    self.webViewPost(webView: self.webView!, baseUrl: PHConfigs.BASE_URL!, url: PHConfigs.BASE_URL! + PHConfigs.CHECKOUT, postData: params)
                }
            }
        }
        
    }
    
    private func Validate() -> String?{
        
        if (PHConfigs.BASE_URL == nil) {
            return "BASE_URL not set";
        }
        
        if ((initRequest?.amount)! <= 0.0) {
            return "Invalid amount";
        }
        if (initRequest?.currency == nil || initRequest?.currency?.count != 3) {
            return "Invalid currency";
        }
        if (initRequest?.merchantId == nil || initRequest?.merchantId?.count == 0) {
            return "Invalid merchant ID";
        }
        if (initRequest?.merchantSecret == nil || initRequest?.merchantSecret?.count == 0) {
            return "Invalid merchant secret";
        }
        return nil
    }
    
     func checkStatus(orderKey : String){
        
        self.progressBar?.startAnimating()
        self.progressBar?.isHidden = false
        
        let params = [
            "order_key" : orderKey
        ]
        
        let headers = [
            "Content-Type": "application/x-www-form-urlencoded"
        ]
        
        
        Alamofire.request(PHConfigs.BASE_URL! + PHConfigs.STATUS, method: .post, parameters: params, encoding: URLEncoding.default, headers: headers)
                .responseObject{ (response: DataResponse<StatusResponse>) in
                    
                    let val = self.validate(request: self.initRequest!, response: response.result.value!)
                    
                    if(val){
                        self.responseListner(response: response.result.value)
                    }else{
                        self.responseListner(response: nil)
                    }
                    
        }
        
    }
    
    private func responseListner(response : StatusResponse?){
        
        guard let lastResponse = response else{
            
            self.dismiss(animated: true, completion: {
                self.delegate?.onResponseReceived(response: nil)
            })
            
            return
        }
        
        if(lastResponse.getStatusState() == StatusResponse.Status.SUCCESS || lastResponse.getStatusState() == StatusResponse.Status.FAILED){
            delegate?.onResponseReceived(response: PHResponse(status: self.getStatusFromResponse(lastResponse: lastResponse), message: "Payment completed. Check response data", data: lastResponse))
        }
        
        self.dismiss(animated: true, completion: {
            self.progressBar?.stopAnimating()
            self.progressBar?.isHidden = true
        })
    }
    
    private func getStatusFromResponse(lastResponse : StatusResponse) -> Int{
        
        if(lastResponse.getStatusState() == StatusResponse.Status.SUCCESS){
            return PHResponse<Any>.STATUS_SUCCESS
        }else{
            return PHResponse<Any>.STATUS_ERROR_PAYMENT
        }
        
    }
    
    private func validate(request : InitRequest,response : StatusResponse)->Bool{
        
        var sb : String?
        
        sb = request.merchantId
        sb = sb! + request.orderId!
        
        guard let amount = request.amount else{
            return false
        }
        
        let decimals =  Int((amount - floor(amount)) * 100)
        
        sb = sb! + String(format: "%0.0f.%02d",floor(amount),decimals)
        
        sb = sb! + request.currency!
        
        sb = sb! + String(format: "%d",(response.status)!)
        
        guard let secret = request.merchantSecret else{
            return false
        }
        
        guard let secretMd5 = secret.md5?.uppercased() else{
            return false
        }
        
        sb = sb! + secretMd5
        
        guard let md5Sig = sb?.md5?.uppercased() else{
            return false
        }
        
        return md5Sig.elementsEqual(response.sign!)
    }
    
}

extension PHViewController : UIWebViewDelegate{
    
    public func webViewDidStartLoad(_ webView: UIWebView) {
        progressBar?.startAnimating()
        progressBar?.isHidden = false
    }
    
    public func webViewDidFinishLoad(_ webView: UIWebView) {
        
        _ = webView.stringByEvaluatingJavaScript(from: "document.documentElement.style.webkitUserSelect='none'")!
        _ = webView.stringByEvaluatingJavaScript(from: "document.documentElement.style.webkitTouchCallout='none'")!
        progressBar?.stopAnimating()
        progressBar?.isHidden = true
    }
    
    
    public func webView(_ webView: UIWebView, shouldStartLoadWith request: URLRequest, navigationType: UIWebViewNavigationType) -> Bool {
        
        
        let html = webView.stringByEvaluatingJavaScript(from: "document.getElementsByTagName('html')[0].innerHTML")
        
        
        let index = html?.range(of: "reference_id\"")
        
        if(index != nil){
            
            let valueStr = "value=\""
            
            guard let result = html?.substring(to: (index?.upperBound)!)else{
                return true
            }
            
            guard var temp = html?.replacingOccurrences(of: result, with: "") else{
                return true
            }
            
            guard let valIndex = temp.range(of: valueStr)else{
                return true
            }
            
            guard let valEnd = temp.range(of: "\">")else{
                return true
            }
            
            let distance = temp.distance(from: valIndex.upperBound, to: valEnd.lowerBound) + valueStr.count
            
            temp = temp.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let valSting = temp.prefix(distance).trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: valueStr).last
            
            
            self.orderKey = valSting
            
        }
        
        if(request.mainDocumentURL?.absoluteString.contains(PHConstants.dummyUrl))!{
            
            
            
            if(self.orderKey != nil){
                self.checkStatus(orderKey: self.orderKey!)
            }
            
            return false
        }
        
        
        return true
    }
    
    public func webView(_ webView: UIWebView, didFailLoadWithError error: Error) {
        
    }
    
    
}

