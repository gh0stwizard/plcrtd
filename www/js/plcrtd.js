$( function() {
  var suffix = '/plcrtd',
      addr = window.location.protocol + '//' + window.location.host
      errors = [
        'Connection error',
        'Bad request',
        'Not implemented',
        'Internal error',
        'Invalid name',
        'Duplicate entry',
        'Entry not found',
        'Missing a database'
      ],
      sizeOptions = [ 1024, 2048, 4096 ],
      pkOptions = [ 'RSA' ], /* DSA is not implemented on server side yet */
      cipherOptions = [
        'DES3',
        'AES128',
        'AES192',
        'AES256'
      ],
      digestOptions = [ 
        'MD5',
        'SHA1',
        'SHA224',
        'SHA256',
        'SHA384',
        'SHA512',
        'RIPEMD160'
      ],
      templateOptions = [ 'Default', 'Self-signed' ];


  function sortByName( a, b ) {
    aName = $.isFunction( a.Name ) ? a.Name() : a.Name;
    bName = $.isFunction( b.Name ) ? b.Name() : b.Name;

    return ( aName == bName ) ? 0 : ( aName < bName ? -1 : 1 );
  }


  function Database ( options ) {
    this.defaults = { name: 'db1', desc: '' };
    options = $.extend( { }, this.defaults, options  );
    
    this.Name = ko.observable( options.name );
    this.Description = ko.observable( options.desc );

    this.isActive = ko.observable( false );
  }


  function PrivateKey ( options ) {
    this.defaults = {
      name:   'key1',
      type:   'RSA',
      size:   2048,
      cipher: 'AES256',
      passwd: null
    };
    options = $.extend( { }, this.defaults, options );

    this.Name = ko.observable( options.name );
    this.Type = ko.observable( options.type );
    this.Size = ko.observable( options.size );
    this.Cipher = ko.observable( options.cipher );
    this.Password = ko.observable( options.passwd );

    this.Encrypted = ko.pureComputed( {
      owner: this,
      read: function ( ) {
        return ( this.Password() ) ? 'Yes' : 'No';
      }
    } );
  }


  function Request ( options ) {
    this.defaults = { 
      name:     'csr1',
      keyname:  '',
      keypass:  '',
      subject:  '/CN=plcrtd',
      digest:   'SHA256'
    };
    options = $.extend( { }, this.defaults, options );

    this.Name = ko.observable( options.name );
    this.KeyName = ko.observable( options.keyname );
    this.KeyPassword = ko.observable( options.keypass );
    this.Subject = ko.observable( options.subject );
    this.Digest = ko.observable( options.digest );
  }

  
  function Certificate ( options ) {
    this.defaults = {
      name:     'crt1',
      desc:     '',
      days:     30,
      serial:   -1,
      /* common certificate options */
      keyname:  '',
      keypass:  '',
      subject:  '/CN=plcrtd',
      digest:   'SHA256',
      /* self-signed certificate options */
      csrname:  '',
      cacrt:    '',
      cakey:    '',
      cakeypw:  '',
      template: 'Default'
    };
    options = $.extend( { }, this.defaults, options );

    this.Name = ko.observable( options.name );
    this.Description = ko.observable( options.desc );
    this.Days = ko.observable( options.days );
    this.Serial = options.serial;

    /* common */
    this.KeyName = ko.observable( options.keyname );
    this.KeyPassword = ko.observable( options.keypass );
    this.Subject = ko.observable( options.subject );
    this.Digest = ko.observable( options.digest );

    /* self-signed */
    this.CsrName = ko.observable( options.csrname );
    this.CACrtName = ko.observable( options.cacrt );
    this.CAKeyName = ko.observable( options.cakey );
    this.CAKeyPassword = ko.observable( options.cakeypw );

    this.Template = ko.observable( options.template );
  }


  function RevocationList ( options ) {
    this.defaults = {
      name:     'crl1',
      desc:     '',
      days:     30,
      cacrt:    '',
      cakey:    '',
      cakeypw:  ''
    };
    options = $.extend( { }, this.defaults, options );

    this.Name = ko.observable( options.name );
    this.Description = ko.observable( options.desc );
    this.Days = ko.observable( options.days );
    this.CACrtName = ko.observable( options.cacrt );
    this.CAKeyName = ko.observable( options.cakey );
    this.CAKeyPassword = ko.observable( options.cakeypw );
  }


  function Page ( args ) {
    this.defaults = { };
    this.args = $.extend( { }, this.defaults, args );

    this.onCreate = ko.observable( false );
    this.onWipe = ko.observable( false );
    this.onTable = ko.observable( false );
    this.List = ko.observableArray( [ ] );
    this.Item = ko.observable();

    this.CreateItem= args.CreateItem
      ? args.CreateItem.bind( this )
      : function ( ) { };

    function Create () {
      this.List.push( this.Item() );
      this.List.sort( sortByName );
      this.CreateToggle();
    }

    this.Create = $.isFunction( args.Create ) 
      ? args.Create.bind( this )
      : Create.bind( this );

    function Remove ( item ) {
      this.List.remove( item );
    }

    this.Remove = $.isFunction( args.Remove )
      ? args.Remove.bind( this )
      : Remove.bind( this );

    function Wipe () {
      this.List.removeAll();
      this.WipeToggle();
    }

    this.Wipe = $.isFunction( args.Wipe )
      ? args.Wipe.bind( this )
      : Wipe.bind( this );

    function CreateToggle () {
      this.onWipe( false );

      if ( this.onCreate() ) {
        this.onCreate( false );
        this.onTable( true );
        this.Item( null );
      } else {
        this.onCreate( true );
        this.onTable( false );
        this.Item( this.CreateItem() );
      }

      return false;
    }

    this.CreateToggle = CreateToggle.bind( this );

    function WipeToggle () {
      this.onCreate( false );

      if ( this.onWipe() ) {
        this.onWipe( false );
        this.onTable( true );
      } else {
        this.onWipe( true );
        this.onTable( false );
      }

      return false;
    }

    this.WipeToggle = WipeToggle.bind( this );
  }


  function AppViewModel() {
    var self = this;

    /*  Data  */

    self.onAJAX = ko.observable( 0 );
    self.errorMessage = ko.observable();
    self.errorDescription = ko.observable();

    /*  Data: show page toggles  */

    self.onAbout = ko.observable( false );
    self.onConfigure = ko.observable( false );
    self.onPrivateKeys = ko.observable( false );
    self.onRequests = ko.observable( false );
    self.onCertificates = ko.observable( false );
    self.onRevoked = ko.observable( false );


    /*  Behaviours  */

    self.About  =       function () { location.hash = 'about';        }
    self.Configure =    function () { location.hash = 'configure';    }
    self.PrivateKeys =  function () { location.hash = 'privatekeys';  }
    self.Requests =     function () { location.hash = 'requests';     }
    self.Certificates = function () { location.hash = 'certificates'; }
    self.Revoked =      function () { location.hash = 'revoked';      }


    /*  Behaviours: Configuration  */

    self.cfg = new Page( {
      CreateItem : function () { return new Database(); },
      Create : function () {
        var iam = this,
            db = iam.Item();

        clearError();

        postJSON( {
          action: 'createdb',
          name: db.Name(),
          desc: db.Description()
        },
        function ( response ) {
          if ( 'name' in response ) {
            iam.List.push( db );
            iam.List.sort( sortByName );
            iam.CreateToggle();
          } else {
            riseError( response.err );
          }
        } );
      },
      Remove : function ( entry ) {
        var iam = this,
            name = entry.Name();

        clearError();

        postJSON( {
          action: 'removedb',
          name: name
        },
        function ( response ) {
          if ( 'name' in response ) {
            if ( iam.Settings().Name() === name ) {
              iam.Settings( null );
            }

            iam.List.remove( entry );
          } else {
            riseError( response.err );
          }
        } );
      },
      Wipe : function ( ) {
        var iam = this;

        clearError();

        postJSON( { action: 'removealldb' }, function ( response ) {
          if ( 'deleted' in response ) {
            iam.Settings( null );
            iam.List.removeAll();
            iam.WipeToggle();
          } else {
            riseError( response.err );
          }
        } );
      }
    } );

    function ActivateDB ( db ) {
      var iam = this,
          name = db.Name();

      clearError();

      postJSON( {
        action: 'switchdb',
        name: name
      },
      function ( response ) {
        if ( 'name' in response ) {
          var dbs = iam.List(),
              len = dbs.length;

          /* mark all as an inactive */
          for ( var i = 0; i < len; i++ ) {
            dbs[i].isActive( false );
          }

          /* activate choosen db */
          db.isActive( true );

          /* retrieve settings */
          iam.Settings( db );
        } else {
          riseError( response.err );
        }
      } );

      return false;
    }

    function SetupDB ( ) {
      var iam = this,
          db = iam.Settings(),
          name = db.Name(),
          desc = db.Description();

      clearError();

      postJSON( {
        action: 'updatedb',
        name: name,
        desc: desc
      },
      function ( response ) {
        if ( 'err' in response ) {
          riseError( response.err );
        }
      } );

      return false;
    }

    function ListDBs ( ) {
      var iam = this;

      clearError();
      iam.List.removeAll();

      postJSON( { action: 'listdbs' }, function ( response ) {
        if ( 'dbs' in response ) {
          var list = response.dbs,
              total = list.length;

          for ( var i = 0; i < total; i++ ) {
            var db = list[i];
            iam.List.push( new Database( { 
              name: db.name,
              desc: db.desc
            } ) );
          }

          iam.List.sort( sortByName );
          iam.Current();
        }
      } );
    }

    function CurrentDB ( ) {
      var iam = this;

      clearError();

      postJSON( { action: 'currentdb' }, function ( response ) {
        if ( 'name' in response ) {
          var dbs = iam.List(),
              len = dbs.length,
              name = response.name;

          for ( var i = 0; i < len; i++ ) {
            var db = dbs[i];

            if ( db.Name() === name ) {
              db.isActive( true );
              iam.Settings( db );
              break;
            }
          }
        }
      } );

      return false;
    }

    $.extend( self.cfg, {
      Activate: ActivateDB.bind( self.cfg ),
      Settings: ko.observable(),
      Setup: SetupDB.bind( self.cfg ),
      ListDBs: ListDBs.bind( self.cfg ),
      Current: CurrentDB.bind( self.cfg )
    } );


    /*  Behaviours: Private Keys  */

    self.pk = new Page( {
      CreateItem : function () { return new PrivateKey(); },
      Create : function () {
        var iam = this,
            key = iam.Item(),
            name = key.Name(),
            type = key.Type(),
            size = key.Size(),
            cipher = key.Cipher(),
            passwd = key.Password();

        clearError();

        postJSON( { 
          action: 'genkey',
          name: name,
          type: type,
          bits: size,
          cipher: cipher,
          passwd: passwd
        },
        function ( response ) {
          if ( 'name' in response ) {
            iam.List.push( key );
            iam.List.sort( sortByName );
            iam.CreateToggle();
          } else {
            riseError( response.err, response.msg );
          }
        } );
      },
      Remove : function ( entry ) {
        var iam = this,
            name = entry.Name();

        clearError();

        postJSON( {
          action: 'removekey',
          name: name
        },
        function ( response ) {
          if ( 'name' in response ) {
            iam.List.remove( entry );
          } else {
            riseError( response.err );
          }
        } );
      },
      Wipe : function () {
        var iam = this;

        clearError();

        postJSON( { action: 'removeallkeys' }, function ( response ) {
          if ( 'deleted' in response ) {
            iam.List.removeAll();
            iam.WipeToggle();
          } else {
            riseError( response.err );
          }
        } );
      }
    } );

    function ListPrivateKeys ( ) {
      var iam = this;

      clearError();
      iam.List.removeAll();

      postJSON( { action: 'listkeys' }, function ( response ) {
        if ( 'keys' in response ) {
          var ary = response.keys,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.List.push( new PrivateKey( ary[i] ) );
          }

          iam.List.sort( sortByName );
        } else {
          riseError( response.err );
        }
      } );
    }

    $.extend( self.pk, {
      ListPKs: ListPrivateKeys.bind( self.pk )
    } );


    /*  Behaviours: Requests  */

    self.csr = new Page( {
      CreateItem : function () { return new Request(); },
      Create : function ( ) {
        var iam = this,
            item = iam.Item(),
            payload = {
              action:   'gencsr',
              name:     item.Name(),
              keyname:  item.KeyName(),
              keypass:  item.KeyPassword(),
              subject:  item.Subject(),
              digest:   item.Digest()
            };

        clearError();

        postJSON( payload, function ( response ) {
          if ( 'name' in response ) {
            iam.List.push( item );
            iam.List.sort( sortByName );
            iam.CreateToggle();
          } else {
            riseError( response.err, response.msg );
          }
        } );
      },
      Remove : function ( entry ) {
        var iam = this,
            name = entry.Name();

        clearError();

        postJSON( {
          action: 'removecsr',
          name: name
        },
        function ( response ) {
          if ( 'name' in response ) {
            iam.List.remove( entry );
          } else {
            riseError( response.err );
          }
        } );
      },
      Wipe : function () {
        var iam = this;

        clearError();

        postJSON( { action: 'removeallcsrs' }, function ( response ) {
          if ( 'deleted' in response ) {
            iam.List.removeAll();
            iam.WipeToggle();
          } else {
            riseError( response.err );
          }
        } );
      }
    } );


    function GetKeys ( ) {
      var iam = this;

      clearError();
      iam.Keys.removeAll();

      postJSON( { action: 'listkeys' }, function ( response ) {
        if ( 'keys' in response ) {
          var ary = response.keys,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.Keys.push( ary[i].name );
          }

          iam.Keys.sort();
        } else {
          riseError( response.err );
        }
      } );

      return false;
    }

    function ListCertificateRequests ( ) {
      var iam = this;

      clearError();
      iam.List.removeAll();

      postJSON( { action: 'listcsrs' }, function ( response ) {
        if ( 'csrs' in response ) {
          var ary = response.csrs,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.List.push( new Request( ary[i] ) );
          }

          iam.List.sort( sortByName );
        } else {
          riseError( response.err );
        }
      } );
    }

    $.extend( self.csr, {
      Keys : ko.observableArray( [ ] ),
      GetKeys  : GetKeys.bind( self.csr ),
      ListCSRs : ListCertificateRequests.bind( self.csr )
    } );


    /*  Behaviours: Certificates  */
    
    self.crt = new Page( {
      CreateItem: function () { return new Certificate(); },
      Create: function ( ) {
        var iam = this,
            item = iam.Item(),
            template = item.Template(),
            payload,
            defaults = {
              action:   'gencrt',
              name:     item.Name(),
              desc:     item.Description(),
              days:     item.Days(),
              template: template
            };

        if ( template == 'Default' ) {
          payload = {
            keyname:  item.KeyName(),
            keypass:  item.KeyPassword(),
            subject:  item.Subject(),
            digest:   item.Digest()
          };
        } else {
          payload = {
            cacrt:    item.CACrtName(),
            cakey:    item.CAKeyName(),
            cakeypw:  item.CAKeyPassword(),
            csrname:  item.CsrName()
          };
        }

        payload = $.extend( { }, defaults, payload );

        clearError();

        postJSON( payload, function ( response ) {
          if ( 'name' in response ) {
            /* update serial */
            item.Serial = iam.Serial();
            iam.GetSerial();

            iam.List.push( item );
            iam.List.sort( sortByName );
            iam.CreateToggle();
          } else {
            riseError( response.err, response.msg );
          }
        } );
      },
      Remove: function ( entry ) {
        var iam = this,
            name = entry.Name();

        clearError();

        postJSON( {
          action: 'removecrt',
          name: name
        },
        function ( response ) {
          if ( 'name' in response ) {
            iam.GetSerial();
            iam.List.remove( entry );
          } else {
            riseError( response.err );
          }
        } );
      },
      Wipe: function () {
        var iam = this;

        clearError();

        postJSON( { action: 'removeallcrts' }, function ( response ) {
          if ( 'deleted' in response ) {
            iam.GetSerial();
            iam.List.removeAll();
            iam.WipeToggle();
          } else {
            riseError( response.err );
          }
        } );
      }
    } );

    function ListCertificates ( ) {
      var iam = this;

      clearError();
      iam.List.removeAll();

      postJSON( { action: 'listcrts' }, function ( response ) {
        if ( 'crts' in response ) {
          var ary = response.crts,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.List.push( new Certificate( ary[i] ) );
          }

          iam.List.sort( sortByName );
        } else {
          riseError( response.err );
        }
      } );
    }

    function GetCSRs ( ) {
      var iam = this;

      clearError();
      iam.CSRs.removeAll();

      postJSON( { action: 'listcsrs' }, function ( response ) {
        if ( 'csrs' in response ) {
          var ary = response.csrs,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.CSRs.push( ary[i].name );
          }

          iam.CSRs.sort();
        } else {
          riseError( response.err );
        }
      } );

      return false;
    }

    function ComputeCrtNames ( ) {
      var result = new Array(),
          crts = this.List(),
          length = crts.length;

      for ( var i = 0; i < length; i++ ) {
        result.push( crts[i].Name() );
      }

      return result;
    }

    function GetSerial ( ) {
      var iam = this;

      clearError();
      iam.Serial( null );

      postJSON( { action: 'getserial' }, function ( response ) {
        if ( 'serial' in response ) {
          iam.Serial( response.serial );
        } else {
          riseError( response.err, response.msg );
        }
      } );

      return false;
    }

    $.extend( self.crt, {
      ListCRTs:   ListCertificates.bind( self.crt ),
      Keys:       ko.observableArray( [ ] ),
      GetKeys:    GetKeys.bind( self.crt ),
      CSRs:       ko.observableArray( [ ] ),
      GetCSRs:    GetCSRs.bind( self.crt ),
      CRTs:       ko.computed( ComputeCrtNames.bind( self.crt ) ),
      Serial:     ko.observable(),
      GetSerial:  GetSerial.bind( self.crt )
    } );


    /*  Behaviours: Revocation Lists  */

    self.crl = new Page( {
      CreateItem: function ( ) { return new RevocationList(); },
      Create: function ( ) {
        var iam = this,
            item = iam.Item(),
            payload = {
              action:   'createcrl',
              name:     item.Name(),
              desc:     item.Description(),
              days:     item.Days(),
              cacrt:    item.CACrtName(),
              cakey:    item.CAKeyName()
            };

        clearError();

        postJSON( payload, function ( response ) {
          if ( 'name' in response ) {
            iam.List.push( item );
            iam.List.sort( sortByName );
            iam.CreateToggle();
          } else {
            riseError( response.err, response.msg );
          }
        } );
      },
      Remove: function ( entry ) {
        var iam = this,
            name = entry.Name();

        clearError();

        postJSON( {
          action: 'removecrl',
          name: name
        },
        function ( response ) {
          if ( 'name' in response ) {
            iam.List.remove( entry );
          } else {
            riseError( response.err );
          }
        } );
      },
      Wipe: function ( ) {
        var iam = this;

        clearError();

        postJSON( { action: 'removeallcrls' }, function ( response ) {
          if ( 'deleted' in response ) {
            iam.List.removeAll();
            iam.WipeToggle();
          } else {
            riseError( response.err );
          }
        } );
      }
    } );

    function ListCRLs ( ) {
      var iam = this;

      clearError();
      iam.List.removeAll();

      postJSON( { action: 'listcrls' }, function ( response ) {
        if ( 'crls' in response ) {
          var ary = response.crls,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.List.push( new RevocationList( ary[i] ) );
          }

          iam.List.sort( sortByName );
        } else {
          riseError( response.err );
        }
      } );
    }

    function GetCRTs ( ) {
      var iam = this;

      clearError();
      iam.CRTs.removeAll();

      postJSON( { action: 'listcrts' }, function ( response ) {
        if ( 'crts' in response ) {
          var ary = response.crts,
              len = ary.length;

          for ( var i = 0; i < len; i++ ) {
            iam.CRTs.push( ary[i].name );
          }

          iam.CRTs.sort();
        } else {
          riseError( response.err );
        }
      } );

      return false;
    }

    function GenerateCRL ( entry ) {
      var iam = this;

    }

    function ActivateCRL ( entry ) {
      this.onActivate( true );
      this.onTable( false );
    }

    function ActivateCRLToggle ( ) {
      this.onActivate( false );
      this.onTable( true );
    }

    function AddCRTtoCRL ( ) {
      return false;
    }

    $.extend( self.crl, {
      ListCRLs:       ListCRLs.bind( self.crl ),
      CRTs:           ko.observableArray( [ ]),
      GetCRTs:        GetCRTs.bind( self.crl ),
      Keys:           ko.observableArray( [ ] ),
      GetKeys:        GetKeys.bind( self.crl ),
      Generate:       GenerateCRL.bind( self.crl ),
      Activate:       ActivateCRL.bind( self.crl ),
      onActivate:     ko.observable(),
      ActivateToggle: ActivateCRLToggle.bind( self.crl ),
      AddToList:      AddCRTtoCRL.bind( self.crl ),
      CRL:            ko.observableArray( [ ] )
    } );


    /*  Helpers  */

    function cleanAll () {
      clearError();
      clearData();
      self.onAbout( false );
      self.onConfigure( false );
      self.onPrivateKeys( false );
      self.onRequests( false );
      self.onCertificates( false );
      self.onRevoked( false );
    }

    function clearError ( ) {
      self.errorMessage( null );
      self.errorDescription( null );
    }

    function clearData ( ) {
      self.cfg.Settings( null );
    }

    function riseError ( ) {
      self.errorMessage( errors[ arguments[0] ] );

      if ( arguments.length > 1  && arguments[1] ) {
        self.errorDescription( arguments[1] );
      }

      /* cleanup */
      self.cfg.Settings( null );

      return false;
    }

    function plusRequest() {
      var n = self.onAJAX() ? self.onAJAX() : 0;
      self.onAJAX( n + 1 );
    }

    function minusRequest() {
      var n = self.onAJAX() ? self.onAJAX() : 1;
      self.onAJAX( n - 1 );
    }

    function postJSON ( payload, success_cb ) {
      plusRequest();

      $.ajax( {
        type: 'POST',
        url: addr + suffix,
        data: payload,
        dataType: 'json',
        success: success_cb,
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
          self.cfg.onTable( true );
          self.cfg.onCreate( false );
          self.cfg.onWipe( false );
          self.cfg.ListDBs();
          break;
        case 'privatekeys':
          self.onPrivateKeys( true );
          self.pk.onTable( true );
          self.pk.onCreate( false );
          self.pk.onWipe( false );
          self.pk.ListPKs();
          break;
        case 'requests':
          self.onRequests( true );
          self.csr.onTable( true );
          self.csr.onCreate( false );
          self.csr.onWipe( false );
          self.csr.GetKeys();
          self.csr.ListCSRs();
          break;
        case 'certificates':
          self.onCertificates( true );
          self.crt.onTable( true );
          self.crt.onCreate( false );
          self.crt.onWipe( false );
          self.crt.GetKeys();
          self.crt.GetCSRs();
          self.crt.GetSerial();
          self.crt.ListCRTs();
          break;
        case 'revoked':
          self.onRevoked( true );
          self.crl.onTable( true );
          self.crl.onCreate( false );
          self.crl.onWipe( false );
          self.crl.GetCRTs();
          self.crl.GetKeys();
          self.crl.ListCRLs();
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
