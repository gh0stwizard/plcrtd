$( function() {
  var suffix = '/plcrtd',
      addr = window.location.protocol + '//' + window.location.host
      ra = addr + suffix + '?',
      errors = [
        'Connection error',
        'Bad request',
        'Not implemented',
        'Internal error'
      ],
      bitsOptions = [ 1024, 2048, 4096 ];

  function sortByName( a, b ) {
    return ( a.name()() == b.name()() ) ? 0 : ( a.name()() < b.name()() ? -1 : 1 );
  }

  function Database ( n, d ) {
    var db = this;

    db.name = ko.observable( n );
    db.description = ko.observable( d );
    db.isActive = ko.observable( false );
    db.editing = ko.observable( false );
    db.edit = function () {
      this.editing( true );
    };

    return db;
  }
  
  function DatabaseSetup ( name ) {
    var setup = this;
    
    setup.dbname = name;
    setup.capath = ko.observable( '/path/to/ca.key' );
    
    return setup;
  }

  function AppViewModel() {
    var self = this;

    /*  Data  */

    self.onAJAX = ko.observable();
    self.errorMessage = ko.observable();
    self.errorDescription = ko.observable();
    
    /*  Data: show page toggles  */

    self.onAbout = ko.observable();
    self.onPrivateKeys = ko.observable();
    self.onRequests = ko.observable();
    self.onCertificates = ko.observable();
    self.onRevoked = ko.observable();

    /*  Data: Configure Page  */

    self.onConfigure = ko.observable();
    self.onCreateDB = ko.observable();
    self.onWipeDBs = ko.observable();

    /*  Data: Configure Page: DB management  */

    self.DB = ko.observable();
    self.DBList = ko.observableArray( [ ] );
    self.onDBTable = ko.observable( false );
    self.DBsetup = ko.observable();

    
    /* Create DB button toggle */
    self.btnCreateDB = function () {
      self.onWipeDBs( false );

      if ( self.onCreateDB() ) {
        self.onCreateDB( false );
        self.onDBTable( true );
        self.DB( null );
      } else {
        self.onCreateDB( true );
        self.onDBTable( false );
        self.DB( new Database( 'db', '' ) );
      }

      return false;
    }

    /* Wipe DBs button toggle */
    self.btnWipeDBs = function () {
      self.onCreateDB( false );

      if ( self.onWipeDBs() ) {
        self.onWipeDBs( false );
        self.onDBTable( true );
      } else {
        self.onWipeDBs( true );
        self.onDBTable( false );
      }

      return false;
    }


    /*  Behaviours  */

    self.About  =       function () { location.hash = 'about';        }
    self.Configure =    function () { location.hash = 'configure';    }
    self.PrivateKeys =  function () { location.hash = 'privatekeys';  }
    self.Requests =     function () { location.hash = 'requests';     }
    self.Certificates = function () { location.hash = 'certificates'; }
    self.Revoked =      function () { location.hash = 'revoked';      }


    self.CreateDB = function () {
      var db = self.DB(),
          name = db.name,
          desc = db.description;

      self.DBList.push( new Database( name, desc ) );
      self.DBList.sort( sortByName );
      self.btnCreateDB();

      return false;
    }

    self.UpdateDB = function ( ) {
      /*  XXX  */
      var name = this.name()(),
          desc = this.description()();
      
      console.log( 'updating: ' + name );
      
    }
    
    self.removeDB = function ( db ) {
      /*  XXX  */
      var name = this.name()();
      
      console.log( 'removing: ' + name );
      
      self.DBList.remove( db );
    }

    self.WipeDBs = function () {
      self.DBList.removeAll();
      self.DBsetup( null );
      self.btnWipeDBs();
    }
    
    self.ActivateDB = function ( db ) {
      var name = db.name()();
      console.log( 'activating: ' + name );
      self.DBsetup( new DatabaseSetup( name ) );
      
      var dbs = self.DBList(),
          len = dbs.length;

      for ( var i = 0; i < len; i++ ) {
        dbs[i].isActive( false );
      }
      
      db.isActive( true );
    }
    
    self.SetupDB = function () {
      var setup = self.DBsetup(),
          name = setup.dbname;
      
      console.log( 'setupdb, db = ' + name );
      
      return false;
    }


    /*  Helpers  */

    function cleanAll () {
      clearError();
      self.onAbout( false );
      self.onConfigure( false );
      self.onPrivateKeys( false );
      self.onRequests( false );
      self.onCertificates( false );
      self.onRevoked( false );
    }

    function clearError () {
      self.errorMessage( null );
      self.errorDescription( null );
    }

    function plusRequest() {
      var n = self.onAJAX() ? self.onAJAX() : 0;
      self.onAJAX( n + 1 );
    }

    function minusRequest() {
      var n = self.onAJAX() ? self.onAJAX() : 1;
      self.onAJAX( n - 1 );
    }

    function postJSON ( url, payload, cb ) {
      plusRequest();

      $.ajax( {
        type: 'POST',
        url: url,
        data: payload,
        dataType: 'json',
        success: cb,
        error: function ( xhr, type, error ) {
          self.errorMessage( error );
        },
        complete: function () {
          minusRequest();
        }
      } );
    }
    
    /*  Router functions  */
    
    function mainPage () { location.hash = 'about'; }

    /*  Setup routers  */

    crossroads.addRoute( '', mainPage );
    crossroads.addRoute( '/', mainPage );

    var pagesRouter = crossroads.addRoute( '{action}' );
    pagesRouter.matched.add( function ( action ) {
      cleanAll();
    
      switch ( action ) {
        case 'configure':
          self.onConfigure( true );
          self.DBList.sort( sortByName );
          break;
        case 'privatekeys':
          self.onPrivateKeys( true );
          break;
        case 'certificates':
          self.onCertificates( true );
          break;
        case 'requests':
          self.onRequests( true );
          break;
        case 'revoked':
          self.onRevoked( true );
          break;
        case 'about':
          self.onAbout( true );
          break;
        default:
          mainPage();
      }
    } );

    /*  Setup hasher  */

    function parseHash ( newHash, oldHash ) {
      if ( newHash == undefined || newHash === "" ) {
        /* location has been switched to '/' */
        mainPage();
      }

      crossroads.parse( newHash );
    }

    hasher.initialized.add( parseHash ); /* parse initial hash */
    hasher.changed.add( parseHash );     /* parse hash changes */
    hasher.init();                       /* start listening for history change */
  }


  ko.applyBindings( new AppViewModel() );
} );
