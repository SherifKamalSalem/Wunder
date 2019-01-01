
import UIKit
import RxSwift
import RxCocoa
import MapKit
import CoreLocation

typealias Weather = ApiController.Weather

class ViewController: UIViewController {
    
    @IBOutlet weak var keyButton: UIButton!
    @IBOutlet weak var geoLocationButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var searchCityName: UITextField!
    @IBOutlet weak var tempLabel: UILabel!
    @IBOutlet weak var humidityLabel: UILabel!
    @IBOutlet weak var iconLabel: UILabel!
    @IBOutlet weak var cityNameLabel: UILabel!
    
    let bag = DisposeBag()
    
    let locationManager = CLLocationManager()
    
    var keyTextField: UITextField?
    
    var cache = [String: Weather]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        style()
        
        keyButton.rx.tap.subscribe(onNext: {
            self.requestKey()
        }).disposed(by:bag)
        
        let currentLocation = locationManager.rx.didUpdateLocations
            .map() { locations in
                return locations[0]
            }
            .filter() { location in
                return location.horizontalAccuracy == kCLLocationAccuracyNearestTenMeters
        }
        
        let geoInput = geoLocationButton.rx.tap.asObservable().do(onNext: {
            self.locationManager.requestWhenInUseAuthorization()
            self.locationManager.startUpdatingLocation()
            
            self.searchCityName.text = "Current Location"
        })
        
        let geoLocation = geoInput.flatMap {
            return currentLocation.take(1)
        }
        
        let geoSearch = geoLocation.flatMap() { location in
            return ApiController.shared.currentWeather(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
                .catchErrorJustReturn(ApiController.Weather.empty)
        }
        
        let searchInput = searchCityName.rx.controlEvent(.editingDidEndOnExit).asObservable()
            .map { self.searchCityName.text }
            .filter { ($0 ?? "").count > 0 }
        
        // Catch Error
        /*let textSearch = searchInput.flatMap { text in
            return ApiController.shared.currentWeather(city: text ?? "Error").do(onNext: { data in
                if let text = text {
                    self.cache[text] = data
                }
            }).catchError { error in
                if let text = text, let cachedData = self.cache[text] {
                    return Observable.just(cachedData)
                } else {
                    return Observable.just(ApiController.Weather.empty)
                }
            }
        }*/
        
        // Retry on Error
        /*let textSearch = searchInput.flatMap { text in
            return ApiController.shared.currentWeather(city: text ?? "Error").do(onNext: { data in
                if let text = text {
                    self.cache[text] = data
                }
            }).retry()
        }*/
        
        // Retry (maxAttemptCount)
        /*let textSearch = searchInput.flatMap { text in
            return ApiController.shared.currentWeather(city: text ?? "Error").do(onNext: { data in
                if let text = text {
                    self.cache[text] = data
                }
            }).retry(3).catchError { error in
                if let text = text, let cachedData = self.cache[text] {
                    return Observable.just(cachedData)
                } else {
                    return Observable.just(ApiController.Weather.empty)
                }
            }
        }*/
        
        // Advanced Retries
        /*let maxAttempts = 4
        
        let textSearch = searchInput.flatMap { text in
            return ApiController.shared.currentWeather(city: text ?? "Error").do(onNext: { data in
                if let text = text {
                    self.cache[text] = data
                }
            }).retryWhen { e in
                e.enumerated().flatMap { (attempt, error) -> Observable<Int> in
                    if attempt >= maxAttempts - 1 {
                        return Observable.error(error)
                    }
                    
                    print("== retrying after \(attempt + 1) seconds ==")
                    
                    return Observable<Int>.timer(Double(attempt + 1), scheduler: MainScheduler.instance).take(1)
                }
            }
        }*/
        
        _ = RxReachability.shared.startMonitor("openweathermap.org")
        
        // Retry Handler
        
        let maxAttempts = 4
        
        let retryHandler: (Observable<Error>) -> Observable<Int> = { e in
            return e.enumerated().flatMap { (attempts, error) -> Observable<Int> in
                if attempts >= maxAttempts - 1 {
                   return Observable.error(error)
                } else if let casted = error as? ApiController.ApiError, casted == .invalidKey {
                    return ApiController.shared.apiKey.filter { $0 != "" }.map { _ in
                        return 1
                    }
                } else if (error as NSError).code == -1009 {
                    return RxReachability.shared.status.filter { $0 == .online }.map { _ in
                        return 1
                    }
                }
                
                print("== retrying after \(attempts + 1) seconds ==")
                
                return Observable<Int>.timer(Double(attempts + 1), scheduler: MainScheduler.instance).take(1)
            }
        }
        
        // Custom Error Handling
        
        let textSearch = searchInput.flatMap { text in
            return ApiController.shared.currentWeather(city: text ?? "Error").do(onNext: { data in
                if let text = text {
                    self.cache[text] = data
                }
            }, onError: { [weak self] e in
                guard let strongSelf = self else { return }
                
                DispatchQueue.main.async {
                    strongSelf.showError(error: e)
                }
            }).retryWhen(retryHandler)
        }
        
        let search = Observable.from([geoSearch, textSearch])
            .merge()
            .asDriver(onErrorJustReturn: ApiController.Weather.empty)
        
        let running = Observable.from([searchInput.map { _ in true },
                                       geoInput.map { _ in true },
                                       search.map { _ in false }.asObservable()])
            .merge()
            .startWith(true)
            .asDriver(onErrorJustReturn: false)
        
        search.map { "\($0.temperature)° C" }
            .drive(tempLabel.rx.text)
            .disposed(by:bag)
        
        search.map { $0.icon }
            .drive(iconLabel.rx.text)
            .disposed(by:bag)
        
        search.map { "\($0.humidity)%" }
            .drive(humidityLabel.rx.text)
            .disposed(by:bag)
        
        search.map { $0.cityName }
            .drive(cityNameLabel.rx.text)
            .disposed(by:bag)
        
        running.skip(1).drive(activityIndicator.rx.isAnimating).disposed(by:bag)
        running.drive(tempLabel.rx.isHidden).disposed(by:bag)
        running.drive(iconLabel.rx.isHidden).disposed(by:bag)
        running.drive(humidityLabel.rx.isHidden).disposed(by:bag)
        running.drive(cityNameLabel.rx.isHidden).disposed(by:bag)
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        Appearance.applyBottomLine(to: searchCityName)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func requestKey() {
        
        func configurationTextField(textField: UITextField!) {
            self.keyTextField = textField
        }
        
        let alert = UIAlertController(title: "Api Key",
                                      message: "Add the api key:",
                                      preferredStyle: UIAlertControllerStyle.alert)
        
        alert.addTextField(configurationHandler: configurationTextField)
        
        alert.addAction(UIAlertAction(title: "Ok", style: UIAlertActionStyle.default, handler:{ (UIAlertAction) in
            ApiController.shared.apiKey.onNext(self.keyTextField?.text ?? "")
        }))
        
        alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.destructive))
        
        self.present(alert, animated: true)
    }
    
    // MARK: - Style
    
    private func style() {
        view.backgroundColor = UIColor.aztec
        searchCityName.textColor = UIColor.ufoGreen
        tempLabel.textColor = UIColor.cream
        humidityLabel.textColor = UIColor.cream
        iconLabel.textColor = UIColor.cream
        cityNameLabel.textColor = UIColor.cream
    }
    
    func showError(error e: Error) {
        if let e = e as? ApiController.ApiError {
            switch (e) {
            case .cityNotFound:
                InfoView.showIn(viewController: self, message: "City Name is invalid")
            case .serverFailure:
                InfoView.showIn(viewController: self, message: "Server error")
            case .invalidKey:
                InfoView.showIn(viewController: self, message: "Key is invalid")
            }
        } else if (e as NSError).code == -1009 {
            InfoView.showIn(viewController: self, message: "No Internet Connection")
        } else {
            InfoView.showIn(viewController: self, message: "An error occured")
        }
    }
}

